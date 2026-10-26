import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/article_identity.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_preparation_service.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/lifecycle_coordinator.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';

const _image = 'https://images.test/gated.png';

FeedItem _item() => FeedItem(
  id: 'gated',
  siteName: 'a',
  title: 'Gated',
  description: '',
  timeAgo: '',
  siteIcon: Icons.rss_feed,
  iconColor: Colors.blue,
  iconBackgroundColor: Colors.white,
  feedUrl: 'https://a.test/feed',
  link: 'https://a.test/article',
  content: '<p>Body</p>',
  imageUrl: _image,
);

/// Pauses inside the gated publication, after the managed rename.
class _PausingMedia extends ArticleMediaStore {
  _PausingMedia({required super.root});
  final inside = Completer<void>();
  final release = Completer<void>();
  @override
  Future<MediaEntry> put(String imageUrl, List<int> bytes) async {
    final entry = await super.put(imageUrl, bytes);
    if (!inside.isCompleted) {
      inside.complete();
      await release.future;
    }
    return entry;
  }
}

void main() {
  late Directory root;
  late LifecycleCoordinator gate;
  late ArticleRecordStore records;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lifecycle-publication-');
    gate = LifecycleCoordinator(directory: Directory('${root.path}/lifecycle'));
    records = ArticleRecordStore(
      FileObservedArticlePersistence(
        stateFile: File('${root.path}/archive.json'),
      ),
    );
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> reset(ArticleMediaStore media) async {
    final handle = await gate.beginReset(cleanupStages: ['archive', 'media']);
    await gate.performCleanupStage(handle, 'archive', () async {
      expect(await records.wipeAll(), isTrue);
    });
    await gate.performCleanupStage(handle, 'media', () async {
      await media.deleteAllManaged();
    });
    await gate.completeReset(handle);
  }

  ArticlePreparationService prep(
    ArticleMediaStore media,
    Future<http.Response> Function() respond,
  ) => ArticlePreparationService(
    recordStore: records,
    mediaStore: media,
    minHostGap: Duration.zero,
    gate: gate,
    client: MockClient((_) => respond()),
  );

  test('reset completed first: stale response creates no file', () async {
    final media = ArticleMediaStore(root: Directory('${root.path}/media'));
    final requested = Completer<void>();
    final release = Completer<http.Response>();
    final service = prep(media, () {
      requested.complete();
      return release.future;
    });
    addTearDown(service.dispose);
    await service.registerArticle(_item(), {'bookmark'}, fullText: false);
    final pending = service.prepareArticle(ArticleRef.of(_item()));
    await requested.future;
    await reset(media);
    release.complete(
      http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-type': 'image/png'},
      ),
    );
    await pending;
    final file = File(
      (await media.pathFor(ArticleMediaStore.fileNameFor(_image)))!,
    );
    expect(await file.exists(), isFalse);
    expect(await records.listRecords(), isEmpty);
  });

  test(
    'publication holding the gate finishes; the later reset removes it',
    () async {
      final media = _PausingMedia(root: Directory('${root.path}/media'));
      final service = prep(
        media,
        () async => http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      addTearDown(service.dispose);
      await service.registerArticle(_item(), {'bookmark'}, fullText: false);
      final pending = service.prepareArticle(ArticleRef.of(_item()));
      await media.inside.future;
      var resetDone = false;
      final resetting = reset(media).then((_) => resetDone = true);
      // The reset must wait for the publication's critical section.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(resetDone, isFalse);
      media.release.complete();
      await pending;
      await resetting;
      final file = File(
        (await media.pathFor(ArticleMediaStore.fileNameFor(_image)))!,
      );
      expect(await file.exists(), isFalse);
      expect(await records.listRecords(), isEmpty);
    },
  );
}
