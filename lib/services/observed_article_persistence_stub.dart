import 'dart:async';

import 'package:hive_ce/hive.dart';

import 'observed_article_persistence.dart';

ObservedArticlePersistence createObservedArticlePersistence(Box box) =>
    _HiveObservedArticlePersistence(box);

class _HiveObservedArticlePersistence implements ObservedArticlePersistence {
  _HiveObservedArticlePersistence(this.box);

  static const _stateKey = 'observedArticlesV1';
  static final Map<String, Future<void>> _tails = {};

  final Box box;

  String get _lockKey => box.name;

  @override
  Future<String?> read() async => box.get(_stateKey) as String?;

  @override
  Future<void> write(String value) => box.put(_stateKey, value);

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
