import 'dart:async';

import 'package:hive_ce/hive.dart';

import 'observed_article_persistence.dart';

ObservedArticlePersistence createObservedArticlePersistence(
  Box box, {
  String fileSuffix = '.observed-articles.json',
}) => _HiveObservedArticlePersistence(
  box,
  // Keep the legacy key for the default suffix so existing stored state is
  // preserved; only alternate state files get a distinct key.
  stateKey: fileSuffix == '.observed-articles.json'
      ? 'observedArticlesV1'
      : 'observedArticlesV1:$fileSuffix',
);

class _HiveObservedArticlePersistence implements ObservedArticlePersistence {
  _HiveObservedArticlePersistence(this.box, {required this.stateKey});

  static final Map<String, Future<void>> _tails = {};

  final Box box;
  final String stateKey;

  String get _lockKey => box.name;

  @override
  Future<String?> read() async => box.get(stateKey) as String?;

  @override
  Future<void> write(String value) => box.put(stateKey, value);

  @override
  Future<ExclusiveResult<T>> runExclusive<T>(
    Future<T> Function() action,
  ) async {
    final previous = _tails[_lockKey] ?? Future<void>.value();
    final release = Completer<void>();
    _tails[_lockKey] = release.future;
    await previous;
    try {
      return ExclusiveResult<T>.acquired(await action());
    } finally {
      release.complete();
    }
  }
}
