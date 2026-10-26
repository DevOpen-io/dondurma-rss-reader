import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import 'article_media_store.dart';
import 'article_record_store.dart';
import 'lifecycle_gate.dart';
import 'observed_article_store.dart';
import 'temp_cache_membership.dart';

/// Factory reset as a journaled lifecycle transaction. The reset intent is
/// durable before any personal data is deleted; each stage is idempotent and
/// acknowledged; an interrupted reset is finished by [recover] at the next
/// start, before any provider or background task reads storage.
abstract final class AppResetService {
  static const bookmarks = 'bookmarks';
  static const subscriptions = 'subscriptions';
  static const feeds = 'feeds';
  static const settings = 'settings';

  /// The full app reset, in the settings-screen order.
  static const allStages = [bookmarks, subscriptions, feeds, settings];

  /// Runs [stages] (name → action) under [gate]. Ungated (null) runs them in
  /// order. Returns false when a stage failed: the reset then stays pending
  /// and blocks new work until [recover] completes it.
  static Future<bool> run(
    LifecycleGate? gate,
    List<(String, Future<void> Function())> stages,
  ) async {
    if (gate == null) {
      try {
        for (final (_, action) in stages) {
          await action();
        }
        return true;
      } catch (error) {
        debugPrint('AppResetService: reset stage failed: $error');
        return false;
      }
    }
    try {
      final reset = await gate.beginReset(
        cleanupStages: [for (final (name, _) in stages) name],
      );
      for (final (name, action) in stages) {
        await gate.performCleanupStage(reset, name, action);
      }
      await gate.completeReset(reset);
      return true;
    } catch (error) {
      debugPrint('AppResetService: reset left pending: $error');
      return false;
    }
  }

  /// Finishes an interrupted reset with provider-free disk cleanup. Call at
  /// every entry point after Hive boxes open and before they are read.
  static Future<void> recover(LifecycleGate gate) =>
      gate.recoverPendingReset(cleanupStages: diskStages());

  /// Provider-free, idempotent disk cleanup for every stage name ever used.
  static Map<String, Future<void> Function()> diskStages() => {
    bookmarks: () => Hive.box('bookmarks').clear(),
    subscriptions: () => Hive.box('feeds').delete('subscriptions'),
    feeds: wipeFeedStorage,
    settings: () => Hive.box('settings').clear(),
  };

  /// Feed-side storage: cache box, durable records, observation history and
  /// the managed media pool. Throws when a sidecar wipe fails, so the stage
  /// is retried instead of acknowledged.
  static Future<void> wipeFeedStorage({ObservedArticleStore? observed}) async {
    final box = Hive.box('feeds');
    Future<void> bumpCacheEpoch() => box.put(
      tempCacheEpochKey,
      DateTime.now().toUtc().microsecondsSinceEpoch,
    );
    await bumpCacheEpoch(); // fence bg writers before the wipe…
    await box.clear();
    await bumpCacheEpoch(); // …and after — clear() erased the first bump.
    final archived = await ArticleRecordStore.forBox(box).wipeAll();
    final history = await (observed ?? ObservedArticleStore.forBox(box))
        .wipeAll();
    await ArticleMediaStore().deleteAllManaged();
    if (!archived || !history) {
      throw StateError('Feed sidecar wipe failed');
    }
  }
}
