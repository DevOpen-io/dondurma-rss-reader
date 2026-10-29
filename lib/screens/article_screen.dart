import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../providers/article_page_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/article_media_store.dart';
import '../services/article_status.dart';
import '../widgets/in_app_browser.dart';
import '../widgets/article/article_circle_buttons.dart';
import '../widgets/article/article_content_skeleton.dart';
import '../widgets/article/article_image_carousel.dart';
import '../widgets/article/article_image_viewer.dart';
import '../widgets/article/read_aloud.dart';
import '../services/article_speech.dart';
import '../widgets/article/article_reading_mode_toggle.dart';
import '../services/image_cache_service.dart';
import '../utils/app_toast.dart';
import '../utils/motion.dart';
import '../utils/offline_status_labels.dart';
import '../utils/share_actions.dart';
import '../utils/time_format.dart';
import '../theme/app_fonts.dart';


const _articleTransitionSettleDelay = Duration(milliseconds: 380);

/// Full-screen article viewer with swipe navigation between articles.
///
/// Wraps individual article pages in a [PageView] so users can swipe
/// left/right to navigate between articles. Each page independently
/// manages its own scroll state, full-text extraction, and reading progress
/// via a scoped [ArticlePageProvider].
class ArticleScreen extends StatefulWidget {
  final List<FeedItem> items;
  final int initialIndex;

  const ArticleScreen({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    // Leaving the article ends reading it aloud.
    unawaited(ArticleSpeech.instance.stop());
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      itemCount: widget.items.length,
      onPageChanged: (index) {
        setState(() => _currentIndex = index);
        unawaited(ArticleSpeech.instance.stopIfNot(widget.items[index]));
        // Mark the new article as read
        context.read<FeedProvider>().markAsRead(widget.items[index]);
      },
      itemBuilder: (context, index) {
        return ChangeNotifierProvider(
          create: (_) => ArticlePageProvider(item: widget.items[index]),
          child: ArticlePage(
            item: widget.items[index],
            currentIndex: index,
            totalCount: widget.items.length,
            isActive: index == _currentIndex,
          ),
        );
      },
    );
  }
}

// =============================================================================
// Individual article page — self-contained with its own scroll, full-text,
// reading progress, and estimated reading time via ArticlePageProvider.
// =============================================================================

/// A single article page: collapsing hero, HTML content, full-text toggle,
/// durable-copy status, and reading progress.
///
/// Public so the desktop three-pane layout can embed it in the reader column
/// with `embedded: true` (no back button or position badge — the pane owns
/// navigation and selection).
class ArticlePage extends StatefulWidget {
  final FeedItem item;
  final int currentIndex;
  final int totalCount;
  final bool isActive;

  /// True when rendered inside the desktop reader pane instead of the
  /// swipeable [ArticleScreen] PageView.
  final bool embedded;

  /// Optional externally-owned scroll controller. The desktop reader pane
  /// supplies one so its visible [Scrollbar] tracks the article scroll
  /// position; mobile pages keep their implicit controllers.
  final ScrollController? scrollController;

  const ArticlePage({
    super.key,
    required this.item,
    required this.currentIndex,
    required this.totalCount,
    required this.isActive,
    this.embedded = false,
    this.scrollController,
  });

  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<ArticlePage> {
  ArticlePageProvider? _articlePageProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _articlePageProvider = context.read<ArticlePageProvider>();
      _articlePageProvider!.addListener(_onProviderChanged);
      Future<void>.delayed(_articleTransitionSettleDelay, () {
        if (!mounted) return;
        _articlePageProvider?.setContentReady();
        unawaited(_maybeCheckAutoFullText());
      });
    });
  }

  @override
  void didUpdateWidget(covariant ArticlePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      unawaited(_maybeCheckAutoFullText());
    }
  }

  Future<void> _maybeCheckAutoFullText() async {
    if (!mounted || !widget.isActive) return;
    final provider =
        _articlePageProvider ?? context.read<ArticlePageProvider>();
    // Refresh (not just first load) so a strip reflects preparation that
    // committed while the page sat inactive (#41 freshness). Auto full
    // text waits for it: a prepared copy opens without the network.
    await provider.refreshSavedCopy();
    if (!mounted || !widget.isActive) return;
    provider.checkAutoFullText(
      context.read<SubscriptionProvider>(),
      context.read<SettingsProvider>(),
    );
  }

  @override
  void dispose() {
    _articlePageProvider?.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    final provider = context.read<ArticlePageProvider>();
    // Only show an error toast for manual full-text attempts.
    // Auto-attempt failures are shown as a subtle inline notice.
    if (mounted && provider.consumeFullTextFailure()) {
      final l10n = AppLocalizations.of(context);
      showAppToast(l10n.fullTextFailed, type: AppToastType.error);
    }
  }

  /// One body widget per reading-settings combination: an identical
  /// instance lets page rebuilds skip the HTML subtree; [_ArticleHtml]
  /// rebuilds itself when the content changes.
  _ArticleHtml? _body;

  _ArticleHtml _articleBody({
    required double fontSize,
    required String? fontFamily,
    required double lineSpacing,
  }) {
    final body = _body;
    if (body != null &&
        body.fontSize == fontSize &&
        body.fontFamily == fontFamily &&
        body.lineSpacing == lineSpacing) {
      return body;
    }
    return _body = _ArticleHtml(
      fontSize: fontSize,
      fontFamily: fontFamily,
      lineSpacing: lineSpacing,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsProvider>();
    final provider = context.watch<ArticlePageProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final String dateStr = widget.item.pubDate != null
        ? DateFormat(
            articleDatePattern(use24HourFormat(context, settings.timeFormat)),
          ).format(widget.item.pubDate!.toLocal())
        : '';

    // Calculate display values
    double baseFontSize = 18.0;
    switch (settings.fontSize) {
      case 'small':
        baseFontSize = 14.0;
        break;
      case 'medium':
        baseFontSize = 18.0;
        break;
      case 'large':
        baseFontSize = 22.0;
        break;
      case 'xl':
        baseFontSize = 26.0;
        break;
    }

    final fontFamily = articleFontFamily(settings.typeface, settings.appFont);

    final hasHero =
        widget.item.imageUrl != null && widget.item.imageUrl!.isNotEmpty;
    final heroLocal = hasHero
        ? provider.localImages[widget.item.imageUrl]
        : null;
    final heroFile = heroLocal == null
        ? null
        : _trustedLocalImage(provider, heroLocal);

    final int? readingMinutes = provider.contentReady
        ? provider.readingMinutes
        : null;
    final readTimeText = readingMinutes == null || readingMinutes <= 0
        ? l10n.lessThanOneMinRead
        : l10n.estimatedReadTime(readingMinutes);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // ── Article content with scroll tracking ──────────────────────
          NotificationListener<ScrollNotification>(
            onNotification: provider.updateReadingProgress,
            child: CustomScrollView(
              controller: widget.scrollController,
              slivers: [
                // ── Collapsing AppBar with hero image ────────────────────
                // Embedded (desktop reader pane): the pane's own toolbar
                // already carries position + open/share, so the app bar is
                // hero-only and unpinned — no double chrome stacked above
                // the article.
                if (!widget.embedded || hasHero)
                SliverAppBar(
                  // Embedded (desktop): scale the hero with the pane instead
                  // of a fixed 280 so tall windows don't waste the fold.
                  expandedHeight: hasHero
                      ? (widget.embedded
                            ? (MediaQuery.sizeOf(context).height * 0.30).clamp(
                                240.0,
                                400.0,
                              )
                            : 280.0)
                      : 0,
                  pinned: !widget.embedded,
                  stretch: true,
                  automaticallyImplyLeading: !widget.embedded,
                  leading: widget.embedded
                      ? const SizedBox.shrink()
                      : CircleBackButton(
                          onPressed: () => Navigator.pop(context),
                        ),
                  title: !widget.embedded && widget.totalCount > 1
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            l10n.articlePosition(
                              widget.currentIndex + 1,
                              widget.totalCount,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        )
                      : null,
                  centerTitle: true,
                  actions: widget.embedded
                      ? null
                      : [
                    // Open in browser (icon only)
                    CircleActionButton(
                      icon: Icons.launch_rounded,
                      onPressed: widget.item.link.isNotEmpty
                          ? () => openArticleLink(
                              context,
                              widget.item.link,
                              title: widget.item.title,
                            )
                          : null,
                      tooltip: l10n.openInBrowser,
                    ),
                    // Share article
                    if (widget.item.link.isNotEmpty)
                      CircleActionButton(
                        icon: Icons.share_rounded,
                        onPressed: () => shareArticleLink(context, widget.item),
                        tooltip: l10n.shareArticle,
                      ),
                    const SizedBox(width: 4),
                      ],
                  flexibleSpace: hasHero
                      ? FlexibleSpaceBar(
                          stretchModes: const [StretchMode.zoomBackground],
                          background: OpenableCoverImage(
                            image: heroFile != null
                                ? FileImage(heroFile)
                                : CachedNetworkImageProvider(
                                    widget.item.imageUrl!,
                                    cacheManager: ArticleCacheManager.instance,
                                  ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // A prepared copy of the hero reads from the
                                // durable media pool, so it shows offline.
                                if (heroFile != null)
                                  Image.file(
                                    heroFile,
                                    fit: BoxFit.cover,
                                    cacheWidth: 900,
                                    errorBuilder: (_, _, _) => Container(
                                      color: colorScheme.surfaceContainerHighest,
                                    ),
                                  )
                                else
                                  CachedNetworkImage(
                                    imageUrl: widget.item.imageUrl!,
                                    cacheManager: ArticleCacheManager.instance,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 900,
                                    maxWidthDiskCache: 900,
                                    errorWidget: (_, _, _) => Container(
                                      color: colorScheme.surfaceContainerHighest,
                                    ),
                                  ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        colorScheme.surface.withValues(
                                          alpha: 0.6,
                                        ),
                                        colorScheme.surface,
                                      ],
                                      stops: const [0.3, 0.75, 1.0],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : null,
                ),

                // ── Article content ──────────────────────────────────────
                // Content width comes from the *pane* constraints, not the
                // window: sizing off MediaQuery squeezed the reader to a ~60px
                // strip when embedded in the desktop three-pane layout.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      // Width comes from the *pane* constraints, not the
                      // window: sizing off MediaQuery squeezed the reader to
                      // a ~60px strip when embedded in the desktop layout.
                      // The desktop "Reading width" setting maps pane width
                      // to a content column; mobile keeps the 720 cap.
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          final mode = widget.embedded
                              ? context
                                  .watch<SettingsProvider>()
                                  .desktopReadingWidth
                              : 'comfortable';
                          final maxW = switch (mode) {
                            _ when !widget.embedded => math.min(w, 720.0),
                            'comfortable' => math.min(w, 760.0),
                            'full' => w,
                            _ => w < 700 ? w : math.min(w * 0.94, 1180.0),
                          };
                          return ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxW),
                            child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: hasHero ? 4 : 20),

                        // Category · date · reading time — one quiet line.
                        Text(
                          [
                            if (widget.item.category.isNotEmpty &&
                                widget.item.category != 'Uncategorized')
                              widget.item.category,
                            if (dateStr.isNotEmpty) dateStr,
                            readTimeText,
                          ].join(' · '),
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Title
                        Text(
                          widget.item.title,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                            height: 1.25,
                            letterSpacing: -0.3,
                          ),
                        ),

                        // Durable-copy status strip (#41): scope label,
                        // media count, wait reason, single retry action.
                        _ArticleStatusStrip(
                          item: widget.item,
                          provider: provider,
                          l10n: l10n,
                          colorScheme: colorScheme,
                        ),

                        const SizedBox(height: 16),

                        // Reading mode toggle — visible affordance for new
                        // users — and read aloud, which needs no link. The
                        // button wraps below when the row runs out of room.
                        if (widget.item.link.isNotEmpty ||
                            ArticleSpeech.supported) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (widget.item.link.isNotEmpty)
                                ArticleReadingModeToggle(
                                  isFullText:
                                      provider.fullTextActive &&
                                      provider.fullTextContent != null,
                                  isLoading: provider.isLoadingFullText,
                                  onToggle: provider.toggleFullText,
                                  colorScheme: colorScheme,
                                  l10n: l10n,
                                ),
                              if (ArticleSpeech.supported)
                                ReadAloudButton(
                                  item: widget.item,
                                  html: () => provider.displayContent,
                                ),
                            ],
                          ),
                        ],
                        if (widget.item.link.isNotEmpty) ...[
                          if (provider.autoFullTextFailed ||
                              provider.fullTextFailed) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(
                                  alpha: 0.3,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 14,
                                    color: colorScheme.onPrimaryContainer
                                        .withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      l10n.fullTextFailed,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onPrimaryContainer
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  TextButton(
                                    onPressed: provider.isLoadingFullText
                                        ? null
                                        : provider.activateFullText,
                                    style: TextButton.styleFrom(
                                      // 48dp touch target.
                                      minimumSize: const Size(48, 48),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    child: Text(
                                      l10n.retry,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],

                        const SizedBox(height: 24),

                        // Shimmer skeleton loading indicator
                        if (!widget.isActive ||
                            !provider.contentReady ||
                            provider.isLoadingFullText) ...[
                          ArticleContentSkeleton(
                            label: provider.isLoadingFullText
                                ? l10n.fullTextLoading
                                : null,
                          ),
                        ] else ...[
                          _articleBody(
                            fontSize: baseFontSize,
                            fontFamily: fontFamily,
                            lineSpacing: settings.lineSpacing,
                          ),
                        ],

                        const SizedBox(height: 28),

                        // Open the original page — one plain button.
                        if (widget.item.link.isNotEmpty)
                          SizedBox(
                            width: double.infinity,
                            child: Tooltip(
                              message: l10n.readOnOriginalWebpage,
                              child: OutlinedButton.icon(
                                onPressed: () => openArticleLink(
                                  context,
                                  widget.item.link,
                                  title: widget.item.title,
                                ),
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  Uri.tryParse(widget.item.link)?.host ??
                                      l10n.openInBrowser,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                ),
                              ),
                            ),
                          ),

                        // Room for the read-aloud bar over the end.
                        ReadAloudSpacer(item: widget.item),
                      ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Read-aloud controls ──────────────────────────────────────
          if (ArticleSpeech.supported)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Center(
                  child: ReadAloudControls(
                    item: widget.item,
                    html: () => provider.displayContent,
                  ),
                ),
              ),
            ),

          // ── Reading progress bar ─────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: ValueListenableBuilder<double>(
                valueListenable: provider.readingProgress,
                builder: (context, progress, _) {
                  if (progress <= 0.01) return const SizedBox.shrink();
                  return Semantics(
                    label: l10n.semanticReadingProgress,
                    value: '${(progress * 100).round()}%',
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: motionDuration(
                        context,
                        const Duration(milliseconds: 150),
                      ),
                      curve: Curves.easeOut,
                      builder: (context, animatedProgress, _) {
                        return LinearProgressIndicator(
                          value: animatedProgress,
                          minHeight: 3.0,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.primary,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Durable-copy status strip (#41)
// =============================================================================

/// Readable-content-first strip: scope label, then the wait reason and
/// media count, then at most one action. A bookmarked item whose durable
/// write failed reads "could not save" — never "ready".
class _ArticleStatusStrip extends StatelessWidget {
  final FeedItem item;
  final ArticlePageProvider provider;
  final AppLocalizations l10n;
  final ColorScheme colorScheme;

  const _ArticleStatusStrip({
    required this.item,
    required this.provider,
    required this.l10n,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final status = provider.recordStatus;
    final unmetered = context.select<FeedProvider, bool>((p) => p.unmetered);

    // Still reading the durable record — show nothing rather than flash a
    // false "could not save" (#41 honesty).
    if (!provider.savedCopyLoaded) return const SizedBox.shrink();

    // Persistent write failed: bookmark claim exists but no record — the
    // on-screen text is session-only and must say so (#41).
    if (status == null) {
      if (!item.isBookmarked) {
        return const SizedBox.shrink();
      }
      return _NoticeBox(
        colorScheme: colorScheme,
        tone: _NoticeTone.warning,
        children: [
          Text(
            l10n.articleStatusCouldNotSave,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Text(
            l10n.articleSessionOnlyNote,
            style: const TextStyle(fontSize: 12),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => unawaited(_retrySave(context)),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                l10n.articleRetrySave,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      );
    }

    final scope = offlineScopeLabel(
      l10n,
      status,
      noneLabel: l10n.articleStatusReadableSession,
    )!;
    final wait = status.waitFor(
      unmeteredNow: unmetered,
      now: DateTime.now().toUtc(),
    );
    final details = <String>[
      if (status.totalMedia > 0)
        l10n.articleImagesCount(status.readyMedia, status.totalMedia),
      ?offlineWaitLabel(l10n, status, wait),
    ];

    // A manual pass may bypass a local backoff but never a server or
    // unknown-origin wait — the button only appears when work is actually
    // reachable (#41: no dead retry affordance). An ownerless record (pre-
    // tombstone) has no claim to prepare for — nothing to retry.
    final showRetry = status.hasActionable && status.scope != ArticleScope.none;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provider.usingArchivedCopy)
          _NoticeBox(
            colorScheme: colorScheme,
            tone: _NoticeTone.info,
            children: [
              Text(
                l10n.articleSavedCopyNotice,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                status.savedAt == null
                    ? l10n.articleSavedDateUnknown
                    : DateFormat.yMMMd(
                        Localizations.localeOf(context).toString(),
                      ).format(status.savedAt!.toLocal()),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      scope,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (showRetry)
                    TextButton(
                      onPressed: () => unawaited(_retryMissing(context)),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        l10n.articleRetryMissing,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
              if (details.isNotEmpty)
                Text(
                  details.join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One article, one pass — may use metered transport but never bypasses
  /// a server Retry-After wait (#41).
  Future<void> _retryMissing(BuildContext context) async {
    final feedProvider = context.read<FeedProvider>();
    await feedProvider.prepareArticleNow(item);
    await provider.refreshSavedCopy();
  }

  Future<void> _retrySave(BuildContext context) async {
    final feedProvider = context.read<FeedProvider>();
    await feedProvider.retrySaveArticle(item);
    await provider.refreshSavedCopy();
  }
}

/// The `href` of the nearest `<a>` around [element], if any.
String? _enclosingLinkHref(dom.Element? element) {
  for (var e = element?.parent; e != null; e = e.parent) {
    if (e.localName == 'a') {
      final href = e.attributes['href']?.trim();
      return href == null || href.isEmpty ? null : href;
    }
  }
  return null;
}

/// Resolves a `file://` image src to its [File] only when it matches the
/// managed-media scheme AND appears in the provider's rewrite map — feed
/// HTML is untrusted, so a raw `file://` URL never reaches the filesystem
/// (#41).
File? _trustedLocalImage(ArticlePageProvider provider, String src) {
  // Exact-rewrite match first — a src carrying a literal '%' must not be
  // dropped just because it can't round-trip through decodeFull.
  if (provider.localImages.containsValue(src)) {
    return ArticleMediaStore.managedFileFromSrc(src);
  }
  final file = ArticleMediaStore.managedFileFromSrc(src);
  if (file == null) return null;
  return provider.localImages.containsValue('file://${file.path}')
      ? file
      : null;
}

/// Carousel src filter — remote http(s) passes; `file://` must resolve to
/// a rewrite-produced managed file.
bool _trustedImageSrc(ArticlePageProvider provider, String src) {
  if (!src.startsWith('file://')) return true;
  return _trustedLocalImage(provider, src) != null;
}

enum _NoticeTone { info, warning }

class _NoticeBox extends StatelessWidget {
  final ColorScheme colorScheme;
  final _NoticeTone tone;
  final List<Widget> children;

  const _NoticeBox({
    required this.colorScheme,
    required this.tone,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _NoticeTone.info => colorScheme.primaryContainer.withValues(alpha: 0.35),
      _NoticeTone.warning => colorScheme.errorContainer.withValues(alpha: 0.35),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// The rendered article body. flutter_html rebuilds its whole styled tree on
/// every rebuild, and an article open sends several page notifications
/// (saved copy, status strip, full-text progress) — so this widget selects
/// only [ArticlePageProvider.displayContent], and the page reuses one
/// instance while the reading settings stay the same.
class _ArticleHtml extends StatelessWidget {
  final double fontSize;
  final String? fontFamily;
  final double lineSpacing;

  const _ArticleHtml({
    required this.fontSize,
    required this.fontFamily,
    required this.lineSpacing,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ArticlePageProvider>();
    final html = context.select<ArticlePageProvider, String>(
      (p) => p.displayContent,
    );
    final colorScheme = Theme.of(context).colorScheme;
    // LayoutBuilder supplies the real content-column width — MediaQuery
    // would give the whole window, breaking embedded panes.
    return LayoutBuilder(
      builder: (context, contentConstraints) {
        final contentWidth = contentConstraints.maxWidth.isFinite
            ? contentConstraints.maxWidth
            : MediaQuery.of(context).size.width;
        return Html(
          data: html,
          extensions: [
            TagExtension(
              tagsToExtend: {"img-carousel"},
              builder: (extensionContext) {
                final urlsStr = extensionContext.attributes['data-urls'] ?? '';
                final urls = urlsStr
                    .split('|')
                    .where((u) => u.isNotEmpty)
                    .where((u) => _trustedImageSrc(provider, u))
                    .toList();
                if (urls.isEmpty) {
                  return const SizedBox.shrink();
                }
                return ArticleImageCarousel(imageUrls: urls);
              },
            ),
            TagExtension(
              tagsToExtend: {"img"},
              builder: (extensionContext) {
                final String? src = extensionContext.attributes['src'];
                if (src == null) {
                  return const SizedBox.shrink();
                }
                // An image inside a link opens the viewer; the viewer
                // offers the link.
                final href = _enclosingLinkHref(extensionContext.element);
                final VoidCallback? openLink = href == null
                    ? null
                    : () => openArticleLink(context, href);
                // Durable media (#41): ready manifest
                // entries were rewritten to file:// — read
                // stored bytes instead of the network.
                // Only paths the rewrite itself produced
                // are trusted: a raw file:// src in feed
                // HTML must never reach the filesystem.
                if (src.startsWith('file://')) {
                  final file = _trustedLocalImage(provider, src);
                  if (file == null) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: OpenableArticleImage(
                      image: FileImage(file),
                      onOpenLink: openLink,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          file,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: OpenableArticleImage(
                    image: CachedNetworkImageProvider(
                      src,
                      cacheManager: ArticleCacheManager.instance,
                    ),
                    onOpenLink: openLink,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: src,
                        cacheManager: ArticleCacheManager.instance,
                        memCacheWidth: 800,
                        maxWidthDiskCache: 800,
                        fit: BoxFit.contain,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          style: {
            "body": Style(
              fontSize: FontSize(fontSize),
              fontFamily: fontFamily,
              fontFamilyFallback: fontFamily == 'monospace'
                  ? monospaceFallback
                  : null,
              color: colorScheme.onSurface,
              lineHeight: LineHeight(lineSpacing),
              margin: Margins.zero,
              padding: HtmlPaddings.zero,
            ),
            "a": Style(
              color: colorScheme.primary,
              textDecoration: TextDecoration.none,
            ),
            "img": Style(
              width: Width(contentWidth),
              margin: Margins.only(top: 12, bottom: 12),
            ),
            "figure": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
            "p": Style(margin: Margins.only(bottom: 12)),
            "br": Style(margin: Margins.zero),
            "hr": Style(margin: Margins.only(top: 16, bottom: 16)),
            "h1": Style(color: colorScheme.onSurface),
            "h2": Style(color: colorScheme.onSurface),
            "h3": Style(color: colorScheme.onSurface),
            "h4": Style(color: colorScheme.onSurface),
            "h5": Style(color: colorScheme.onSurface),
            "h6": Style(color: colorScheme.onSurface),
          },
          onLinkTap: (url, attributes, element) {
            if (url != null && url.isNotEmpty) {
              openArticleLink(context, url);
            }
          },
        );
      },
    );
  }
}
