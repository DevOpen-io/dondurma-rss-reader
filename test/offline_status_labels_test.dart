import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations_en.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/article_status.dart';
import 'package:ice_cream_rss_reader/utils/offline_status_labels.dart';

/// The list row and the article strip share one scope/wait vocabulary;
/// only an ownerless `none` scope reads differently (row: nothing, article:
/// "readable this session").
void main() {
  final l10n = AppLocalizationsEn();

  ArticleStatus status({
    Set<String> owners = const {'bookmark'},
    String? bodySource = 'extracted',
    bool hasBody = true,
    bool bodyDue = false,
    int readyMedia = 0,
    int totalMedia = 0,
    DateTime? earliestRetryAt,
    DateTime? earliestServerRetryAt,
  }) => ArticleStatus(
    owners: owners,
    bodyState: MediaState.ready,
    bodySource: bodySource,
    hasBody: hasBody,
    bodyDue: bodyDue,
    readyMedia: readyMedia,
    totalMedia: totalMedia,
    goneMedia: 0,
    goneBody: false,
    earliestRetryAt: earliestRetryAt,
    earliestServerRetryAt: earliestServerRetryAt,
    hasServerWait: earliestServerRetryAt != null,
    hasDueWork: bodyDue,
    hasActionable: false,
    savedAt: null,
  );

  group('offlineScopeLabel', () {
    test('maps every saved and cached scope', () {
      expect(
        offlineScopeLabel(l10n, status(), noneLabel: null),
        l10n.articleStatusSavedCopyReady,
      );
      expect(
        offlineScopeLabel(l10n, status(bodyDue: true), noneLabel: null),
        l10n.articleStatusTextSaved,
      );
      expect(
        offlineScopeLabel(l10n, status(hasBody: false), noneLabel: null),
        l10n.articleStatusSaveRequested,
      );
      expect(
        offlineScopeLabel(l10n, status(owners: {'tempCache'}), noneLabel: null),
        l10n.articleStatusReadyInCache,
      );
      expect(
        offlineScopeLabel(
          l10n,
          status(owners: {'tempCache'}, bodyDue: true),
          noneLabel: null,
        ),
        l10n.articleStatusTextCached,
      );
    });

    test('an RSS body says so for saved and cached text', () {
      expect(
        offlineScopeLabel(
          l10n,
          status(bodySource: 'rss', bodyDue: true),
          noneLabel: null,
        ),
        l10n.articleStatusRssSaved,
      );
      expect(
        offlineScopeLabel(
          l10n,
          status(owners: {'tempCache'}, bodySource: 'rss', bodyDue: true),
          noneLabel: null,
        ),
        l10n.articleStatusRssCached,
      );
    });

    test('an ownerless record uses the caller label', () {
      final ownerless = status(owners: const {});
      expect(ownerless.scope, ArticleScope.none);
      expect(offlineScopeLabel(l10n, ownerless, noneLabel: null), isNull);
      expect(
        offlineScopeLabel(
          l10n,
          ownerless,
          noneLabel: l10n.articleStatusReadableSession,
        ),
        l10n.articleStatusReadableSession,
      );
    });
  });

  group('offlineWaitLabel', () {
    final at = DateTime.utc(2026, 1, 1, 9, 30);
    final hm = DateFormat.Hm().format(at.toLocal());

    test('fixed reasons', () {
      final s = status();
      expect(
        offlineWaitLabel(l10n, s, ArticleWait.unavailable),
        l10n.articleWaitUnavailable,
      );
      expect(
        offlineWaitLabel(l10n, s, ArticleWait.unmetered),
        l10n.articleWaitUnmetered,
      );
      expect(
        offlineWaitLabel(l10n, s, ArticleWait.preparing),
        l10n.articleWaitPreparing,
      );
      expect(offlineWaitLabel(l10n, s, ArticleWait.none), isNull);
    });

    test('server wait shows the server-stamped time only', () {
      expect(
        offlineWaitLabel(
          l10n,
          status(earliestServerRetryAt: at),
          ArticleWait.serverWait,
        ),
        '${l10n.articleWaitServer} · ${l10n.articleWaitRetryEarliest(hm)}',
      );
      // A local backoff stamp never leaks into the server label.
      expect(
        offlineWaitLabel(
          l10n,
          status(earliestRetryAt: at),
          ArticleWait.serverWait,
        ),
        l10n.articleWaitServer,
      );
    });

    test('retry shows the earliest local time, or nothing without one', () {
      expect(
        offlineWaitLabel(l10n, status(earliestRetryAt: at), ArticleWait.retry),
        l10n.articleWaitRetryEarliest(hm),
      );
      expect(offlineWaitLabel(l10n, status(), ArticleWait.retry), isNull);
    });
  });
}
