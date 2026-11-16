import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/article_status.dart';

/// Scope label shared by the list row and the article strip (#41) —
/// distinguishes temporary cache from permanent bookmark claims.
///
/// An ownerless record ([ArticleScope.none]) claims nothing: the row shows
/// no label, the open article says it is readable this session — so the
/// caller supplies [noneLabel].
///
/// [summaryOnly]: the stored body is only the feed's short excerpt (see
/// `ArticlePageProvider.savedBodyIsFeedSummary`). A bookmark then says so —
/// "ready" would promise an article that cannot be read offline.
String? offlineScopeLabel(
  AppLocalizations l10n,
  ArticleStatus status, {
  required String? noneLabel,
  bool summaryOnly = false,
}) {
  final rss = status.bodySource == 'rss';
  return switch (status.scope) {
    ArticleScope.savedReady || ArticleScope.savedText when summaryOnly =>
      l10n.articleStatusSummaryOnlySaved,
    ArticleScope.savedReady =>l10n.articleStatusSavedCopyReady,
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
    // Transient: work is running right now and asks nothing of the reader.
    case ArticleWait.preparing:
    case ArticleWait.none:
      return null;
  }
}

// Usability test 2026-10-30: cache housekeeping ("Ready in cache",
// "Images 1/1") read as internal jargon. Labels below stay honest (#41) but
// only speak when the reader asked for the copy or something is missing.

/// Whether a list row names the article's offline scope. Caching is
/// automatic, so cached copies say nothing; a bookmark speaks up only while
/// its copy is incomplete — a finished one is what the bookmark promises.
bool rowNamesScope(ArticleScope scope) =>
    scope == ArticleScope.saveRequested || scope == ArticleScope.savedText;

/// The article's image count, only while some images are still missing.
String? articleImagesDetail(AppLocalizations l10n, ArticleStatus status) =>
    status.readyMedia < status.totalMedia
    ? l10n.articleImagesCount(status.readyMedia, status.totalMedia)
    : null;

/// Whether the article strip says anything about the stored copy.
///
/// Device test 2026-11-16: fresh articles showed "RSS text cached", a
/// retry button and "Images 0/1" while the image was on screen. A copy
/// held only by the temporary cache is automatic housekeeping the reader
/// never asked for — while online the page loads live, and bookmarking is
/// how to keep an article — so it shows no scope, count, wait reason or
/// retry. A bookmark always tells the truth about its copy, and an
/// ownerless record warns "readable this session" (#41). The archived-copy
/// notice and "could not save" are separate and unaffected.
bool articleStripSpeaks(ArticleScope scope) =>
    scope != ArticleScope.cachedReady && scope != ArticleScope.cachedText;
