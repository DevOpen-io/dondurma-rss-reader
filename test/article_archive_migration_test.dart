import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/article_identity.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';

const _a = 'https://a.test/feed';
const _b = 'https://b.test/feed';

FeedItem _item(String feed, String id) => FeedItem(
  id: id,
  siteName: feed,
  title: id,
  description: '',
  feedUrl: feed,
);

Map<String, dynamic> _legacyRecord(
  String id,
  String feed, {
  String? body,
  Map<String, dynamic>? media,
}) => {
  'id': id,
  'feedUrl': feed,
  'body': ?body,
  'owners': ['bookmark'],
  'generation': 1,
  'media': ?media,
};

ArticleRecordStore _store(Directory root, List<FeedItem> known) =>
    ArticleRecordStore(
      FileObservedArticlePersistence(
        stateFile: File('${root.path}/archive.v2.json'),
      ),
      legacy: FileObservedArticlePersistence(
        stateFile: File('${root.path}/archive.json'),
      ),
      knownInstances: () => known,
    );

Future<String> _isolateFirstAccess(String root) async {
  final store = _store(Directory(root), [_item(_a, 'solo')]);
  final record = await store.read(ArticleRef(_a, 'solo'));
  return record?.body ?? 'missing';
}

void main() {
  late Directory root;
  late File legacy;
  late File v2;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('archive-migration-');
    legacy = File('${root.path}/archive.json');
    v2 = File('${root.path}/archive.v2.json');
  });
  tearDown(() => root.delete(recursive: true));

  Future<String> seedLegacy({
    Map<String, dynamic> records = const {},
    Map<String, dynamic> seen = const {},
    int epoch = 42,
  }) async {
    final raw = jsonEncode({
      'schema': 1,
      'records': records,
      'seen': seen,
      'epoch': epoch,
    });
    await legacy.writeAsString(raw);
    return raw;
  }

  test('unambiguous legacy record is re-keyed to its instance', () async {
    final raw = await seedLegacy(
      records: {'solo': _legacyRecord('solo', _a, body: '<p>A</p>')},
    );
    final store = _store(root, [_item(_a, 'solo')]);
    final record = await store.read(ArticleRef(_a, 'solo'));
    expect(record!.body, '<p>A</p>');
    expect(record.owners, {'bookmark'});
    expect(await store.read(ArticleRef(_b, 'solo')), isNull);
    // Legacy bytes are migration input only.
    expect(await legacy.readAsString(), raw);
  });

  test('shared GUID record is quarantined: bytes kept, never an instance '
      'copy', () async {
    final media = {
      'https://img.test/x.png': {
        'file': 'm_0000000000000001',
        'byteSize': 3,
        'state': 'ready',
      },
    };
    await seedLegacy(
      records: {
        'shared': _legacyRecord(
          'shared',
          _a,
          body: '<p>mixed</p>',
          media: media,
        ),
      },
    );
    final store = _store(root, [_item(_a, 'shared'), _item(_b, 'shared')]);
    expect(await store.read(ArticleRef(_a, 'shared')), isNull);
    expect(await store.read(ArticleRef(_b, 'shared')), isNull);
    final gc = await store.listRecordsForGc();
    expect(gc.clean, isTrue);
    expect(gc.records, isEmpty);
    expect(gc.quarantine.single.body, '<p>mixed</p>');
    expect(gc.quarantine.single.media.values.single.file, 'm_0000000000000001');
  });

  test('a record whose stored feed disagrees with the only instance is '
      'quarantined', () async {
    await seedLegacy(records: {'x': _legacyRecord('x', _a, body: 'A')});
    final store = _store(root, [_item(_b, 'x')]);
    expect(await store.read(ArticleRef(_b, 'x')), isNull);
    expect((await store.listRecordsForGc()).quarantine, hasLength(1));
  });

  test(
    'migration is persisted once and idempotent; new writes survive',
    () async {
      final raw = await seedLegacy(
        records: {'solo': _legacyRecord('solo', _a, body: 'A')},
      );
      final first = _store(root, [_item(_a, 'solo')]);
      await first.read(ArticleRef(_a, 'solo'));
      expect(await v2.exists(), isTrue);
      await first.write(
        ArticleRecord(id: 'new', feedUrl: _b, owners: const {'tempCache'}),
      );
      // A restart with different known instances must not re-migrate.
      final restarted = _store(root, const []);
      expect((await restarted.read(ArticleRef(_a, 'solo')))!.body, 'A');
      expect(await restarted.read(ArticleRef(_b, 'new')), isNotNull);
      expect(await legacy.readAsString(), raw);
    },
  );

  test(
    'a torn staging file from an interrupted migration is ignored',
    () async {
      await seedLegacy(records: {'solo': _legacyRecord('solo', _a, body: 'A')});
      // Process died after writing the staged copy, before the rename.
      await File('${v2.path}.tmp.123-0-0').writeAsString('{"schema":2,"recor');
      final store = _store(root, [_item(_a, 'solo')]);
      expect((await store.read(ArticleRef(_a, 'solo')))!.body, 'A');
    },
  );

  test(
    'epoch carries over: old fences stay rejected after migration',
    () async {
      await seedLegacy(epoch: 1000);
      final store = _store(root, const []);
      expect(await store.currentEpoch(), 1000);
      final ref = ArticleRef(_a, 'x');
      ArticleRecord create(ArticleRecord? _) =>
          ArticleRecord(id: 'x', feedUrl: _a, owners: const {'bookmark'});
      expect(
        await store.mutate(ref, create, expectedEpoch: 999),
        StoreWriteResult.rejected,
      );
      expect(
        await store.mutate(ref, create, expectedEpoch: 1000),
        StoreWriteResult.applied,
      );
    },
  );

  test('reset wipes both archives and bumps past both epochs', () async {
    await seedLegacy(
      records: {'solo': _legacyRecord('solo', _a, body: 'A')},
      epoch: 5000,
    );
    final store = _store(root, [_item(_a, 'solo')]);
    await store.read(ArticleRef(_a, 'solo'));
    expect(await store.wipeAll(), isTrue);
    final legacyState = jsonDecode(await legacy.readAsString()) as Map;
    expect(legacyState['records'], isEmpty);
    expect(await store.read(ArticleRef(_a, 'solo')), isNull);
    expect(await store.currentEpoch(), greaterThan(5000));
    // A post-reset access never re-migrates the wiped legacy content.
    expect((await store.listRecordsForGc()).quarantine, isEmpty);
  });

  test('ambiguous first-seen stamps go to every known instance', () async {
    await seedLegacy(seen: {'shared': '2026-01-01T00:00:00.000Z'});
    final store = _store(root, [_item(_a, 'shared'), _item(_b, 'shared')]);
    final seen = await store.allFirstSeen();
    expect(seen.keys.toSet(), {
      ArticleRef(_a, 'shared'),
      ArticleRef(_b, 'shared'),
    });
  });

  test('concurrent first accesses agree on one migration', () async {
    await seedLegacy(records: {'solo': _legacyRecord('solo', _a, body: 'A')});
    final stores = [
      for (var i = 0; i < 4; i++) _store(root, [_item(_a, 'solo')]),
    ];
    final bodies = await Future.wait([
      for (final store in stores)
        store.read(ArticleRef(_a, 'solo')).then((r) => r?.body),
    ]);
    expect(bodies, everyElement('A'));
  });

  test('a background isolate may perform the first access', () async {
    await seedLegacy(records: {'solo': _legacyRecord('solo', _a, body: 'A')});
    final path = root.path;
    expect(await Isolate.run(() => _isolateFirstAccess(path)), 'A');
    final foreground = _store(root, const []);
    expect((await foreground.read(ArticleRef(_a, 'solo')))!.body, 'A');
  });

  test(
    'forBox reads known instances from the cache and bookmark boxes',
    () async {
      Hive.init(root.path);
      final feeds = await Hive.openBox('feeds');
      final bookmarks = await Hive.openBox('bookmarks');
      addTearDown(Hive.close);
      await feeds.put('cachedItemsJson', jsonEncode([_item(_a, 'c').toJson()]));
      await bookmarks.put(
        'bookmarkedItemsJson',
        jsonEncode([_item(_b, 'k').toJson()]),
      );
      await File('${feeds.path}.article-archive.json').writeAsString(
        jsonEncode({
          'schema': 1,
          'records': {
            'c': _legacyRecord('c', _a, body: 'cached'),
            'k': _legacyRecord('k', _b, body: 'kept'),
          },
          'seen': {},
          'epoch': 1,
        }),
      );
      final store = ArticleRecordStore.forBox(feeds);
      expect((await store.read(ArticleRef(_a, 'c')))!.body, 'cached');
      expect((await store.read(ArticleRef(_b, 'k')))!.body, 'kept');
    },
  );
}
