import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/article_status.dart';

/// Scope label shared by the list row and the article strip (#41) —
/// distinguishes temporary cache from permanent bookmark claims.
///
/// An ownerless record ([ArticleScope.none]) claims nothing: the row shows
/// no label, the open article says it is readable this session — so the
/// caller supplies [noneLabel].
String? offlineScopeLabel(
  AppLocalizations l10n,
  ArticleStatus status, {
  required String? noneLabel,
}) {
  final rss = status.bodySource == 'rss';
  return switch (status.scope) {
    ArticleScope.savedReady => l10n.articleStatusSavedCopyReady,
    ArticleScope.savedText =>
      rss ? l10n.articleStatusRssSaved : l10n.articleStatusTextSaved,
    ArticleScope.saveRequested => l10n.articleStatusSaveRequested,
    ArticleScope.cachedReady => l10n.articleStatusReadyInCache,
    ArticleScope.cachedText =>
      rss ? l10n.articleStatusRssCached : l10n.articleStatusTextCached,
    ArticleScope.none => noneLabel,
  };
}

/// Optional second reason line — why preparation is still incomplete.
String? offlineWaitLabel(
  AppLocalizations l10n,
  ArticleStatus status,
  ArticleWait wait,
) {
  // Formatted only in the arms that show a time.
  String earliest(DateTime at) =>
      l10n.articleWaitRetryEarliest(DateFormat.Hm().format(at.toLocal()));

  switch (wait) {
    case ArticleWait.unavailable:
      return l10n.articleWaitUnavailable;
    case ArticleWait.serverWait:
      // The server-wait timestamp comes from the SERVER-stamped earliest;
      // mixing in a local backoff would misstate how long the source asked
      // us to wait (#41).
      final at = status.earliestServerRetryAt;
      return at == null
          ? l10n.articleWaitServer
          : '${l10n.articleWaitServer} · ${earliest(at)}';
    case ArticleWait.retry:
      // waitFor only returns retry when a future wait exists.
      final at = status.earliestRetryAt;
      return at == null ? null : earliest(at);
    case ArticleWait.unmetered:
      return l10n.articleWaitUnmetered;
    case ArticleWait.preparing:
      return l10n.articleWaitPreparing;
    case ArticleWait.none:
      return null;
  }
}
