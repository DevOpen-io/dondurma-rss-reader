import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../providers/article_page_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../widgets/in_app_browser.dart';
import '../widgets/article/article_circle_buttons.dart';
import '../widgets/article/article_content_skeleton.dart';
import '../widgets/article/article_image_carousel.dart';
import '../widgets/article/article_reading_mode_toggle.dart';
import '../widgets/article/article_translation_sheet.dart';
import '../services/image_cache_service.dart';
import 'dart:math' as math;

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
        // Mark the new article as read
        context.read<FeedProvider>().markAsRead(widget.items[index].id);
      },
      itemBuilder: (context, index) {
        return ChangeNotifierProvider(
          create: (_) => ArticlePageProvider(item: widget.items[index]),
          child: _ArticlePage(
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

class _ArticlePage extends StatefulWidget {
  final FeedItem item;
  final int currentIndex;
  final int totalCount;
  final bool isActive;

  const _ArticlePage({
    required this.item,
    required this.currentIndex,
    required this.totalCount,
    required this.isActive,
  });

  @override
  State<_ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<_ArticlePage> {
  ArticlePageProvider? _articlePageProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _articlePageProvider = context.read<ArticlePageProvider>();
      _articlePageProvider!.setContentReady();
      _articlePageProvider!.addListener(_onProviderChanged);
      _articlePageProvider!.checkAutoFullText(context.read<SubscriptionProvider>());
    });
  }

  @override
  void dispose() {
    _articlePageProvider?.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    final provider = context.read<ArticlePageProvider>();
    if (provider.fullTextFailed && mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.fullTextFailed)));
    }
  }

  // ---------------------------------------------------------------------------
  // Translation
  // ---------------------------------------------------------------------------

  void _showTranslationSheet(
    BuildContext context,
    ArticlePageProvider provider,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ArticleTranslationSheet(provider: provider),
    );
  }

  // ---------------------------------------------------------------------------
  // URL opening
  // ---------------------------------------------------------------------------

  void _openUrl(BuildContext context, String url, {String? title}) {
    String cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.invalidUrlFormat)));
      return;
    }

    final settings = context.read<SettingsProvider>();
    final adBlock = settings.adBlockEnabled;
    final browserMode = settings.browserMode;
    openInAppBrowser(
      context,
      cleanUrl,
      title: title,
      adBlockEnabled: adBlock,
      browserMode: browserMode,
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
            'MMM d, yyyy  h:mm a',
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

    String? fontFamily;
    switch (settings.typeface) {
      case 'serif':
        fontFamily = 'serif, Georgia, Times New Roman';
        break;
      case 'sans-serif':
        fontFamily = 'sans-serif, Arial, Helvetica';
        break;
      case 'mono':
        fontFamily = 'monospace, Courier';
        break;
      case 'system':
      default:
        fontFamily = null;
        break;
    }

    // Get content from provider
    final String displayContent = provider.displayContent;
    final hasHero =
        widget.item.imageUrl != null && widget.item.imageUrl!.isNotEmpty;

    // Estimated reading time
    final readingMinutes = provider.readingMinutes;
    final readTimeText = readingMinutes <= 0
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
              slivers: [
                // ── Collapsing AppBar with hero image ────────────────────
                SliverAppBar(
                  expandedHeight: hasHero ? 280 : 0,
                  pinned: true,
                  stretch: true,
                  leading: CircleBackButton(
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: widget.totalCount > 1
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
                  actions: [
                    // Open in browser (icon only)
                    CircleActionButton(
                      icon: Icons.launch_rounded,
                      onPressed: widget.item.link.isNotEmpty
                          ? () => _openUrl(
                              context,
                              widget.item.link,
                              title: widget.item.title,
                            )
                          : null,
                      tooltip: l10n.openInBrowser,
                    ),
                    // Translate article — toggle: tap again to restore original
                    CircleActionButton(
                      icon: Icons.translate_rounded,
                      isActive: provider.isTranslated,
                      onPressed: provider.isTranslated
                          ? () => provider.clearTranslation()
                          : () => _showTranslationSheet(context, provider),
                      tooltip: l10n.translateArticle,
                    ),
                    // Share article
                    if (widget.item.link.isNotEmpty)
                      CircleActionButton(
                        icon: Icons.share_rounded,
                        onPressed: () {
                          SharePlus.instance.share(
                            ShareParams(
                              text: widget.item.link,
                              subject: widget.item.title,
                            ),
                          );
                        },
                        tooltip: l10n.shareArticle,
                      ),
                    const SizedBox(width: 4),
                  ],
                  flexibleSpace: hasHero
                      ? FlexibleSpaceBar(
                          stretchModes: const [StretchMode.zoomBackground],
                          background: Stack(
                            fit: StackFit.expand,
                            children: [
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
                        )
                      : null,
                ),

                // ── Article content ──────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: math.max(
                        20.0,
                        (MediaQuery.of(context).size.width - 680) / 2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: hasHero ? 4 : 20),

                        // Category + Date row
                        Row(
                          children: [
                            if (widget.item.category.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  widget.item.category.toUpperCase(),
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            if (widget.item.category.isNotEmpty &&
                                dateStr.isNotEmpty)
                              const SizedBox(width: 10),
                            if (dateStr.isNotEmpty)
                              Expanded(
                                child: Text(
                                  dateStr,
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.45,
                                    ),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 16),

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

                        const SizedBox(height: 12),

                        // Estimated reading time
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 15,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.45,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              readTimeText,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Reading mode toggle — visible affordance for new users
                        if (widget.item.link.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ArticleReadingModeToggle(
                            isFullText: provider.fullTextActive &&
                                provider.fullTextContent != null,
                            isLoading: provider.isLoadingFullText,
                            onToggle: provider.toggleFullText,
                            colorScheme: colorScheme,
                            l10n: l10n,
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Shimmer skeleton loading indicator
                        if (!provider.contentReady ||
                            provider.isLoadingFullText) ...[
                          ArticleContentSkeleton(
                            label: provider.isLoadingFullText
                                ? l10n.fullTextLoading
                                : null,
                          ),
                        ] else ...[
                          // Rich HTML content
                          Html(
                            data: displayContent,
                            extensions: [
                              TagExtension(
                                tagsToExtend: {"img-carousel"},
                                builder: (extensionContext) {
                                  final urlsStr =
                                      extensionContext
                                          .attributes['data-urls'] ??
                                      '';
                                  final urls = urlsStr
                                      .split('|')
                                      .where((u) => u.isNotEmpty)
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
                                  final String? src =
                                      extensionContext.attributes['src'];
                                  if (src == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: CachedNetworkImage(
                                        imageUrl: src,
                                        cacheManager:
                                            ArticleCacheManager.instance,
                                        memCacheWidth: 800,
                                        maxWidthDiskCache: 800,
                                        fit: BoxFit.contain,
                                        errorWidget: (_, _, _) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                            style: {
                              "body": Style(
                                fontSize: FontSize(baseFontSize),
                                fontFamily: fontFamily,
                                color: colorScheme.onSurface,
                                lineHeight: LineHeight(settings.lineSpacing),
                                margin: Margins.zero,
                                padding: HtmlPaddings.zero,
                              ),
                              "a": Style(
                                color: colorScheme.primary,
                                textDecoration: TextDecoration.none,
                              ),
                              "img": Style(
                                width: Width(
                                  MediaQuery.of(context).size.width - 40,
                                ),
                                margin: Margins.only(top: 12, bottom: 12),
                              ),
                              "figure": Style(
                                margin: Margins.zero,
                                padding: HtmlPaddings.zero,
                              ),
                              "p": Style(margin: Margins.only(bottom: 12)),
                              "br": Style(margin: Margins.zero),
                              "hr": Style(
                                margin: Margins.only(top: 16, bottom: 16),
                              ),
                              "h1": Style(color: colorScheme.onSurface),
                              "h2": Style(color: colorScheme.onSurface),
                              "h3": Style(color: colorScheme.onSurface),
                              "h4": Style(color: colorScheme.onSurface),
                              "h5": Style(color: colorScheme.onSurface),
                              "h6": Style(color: colorScheme.onSurface),
                            },
                            onLinkTap: (url, attributes, element) {
                              if (url != null && url.isNotEmpty) {
                                _openUrl(context, url);
                              }
                            },
                          ),
                        ],

                        const SizedBox(height: 28),

                        // Bottom action row — "Open Original" button
                        if (widget.item.link.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.15,
                                ),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  l10n.readOnOriginalWebpage,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.5,
                                    ),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: () => _openUrl(
                                      context,
                                      widget.item.link,
                                      title: widget.item.title,
                                    ),
                                    icon: const Icon(
                                      Icons.public_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      Uri.tryParse(widget.item.link)?.host ??
                                          l10n.openInBrowser,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
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
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      builder: (context, animatedProgress, _) {
                        return LinearProgressIndicator(
                          value: animatedProgress,
                          minHeight: 3.0,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
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


