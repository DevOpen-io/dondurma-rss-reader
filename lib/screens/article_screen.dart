import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../providers/article_page_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../widgets/in_app_browser.dart';

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
  @override
  void initState() {
    super.initState();
    // Defer heavy content rendering by one frame so the slide-in
    // transition plays smoothly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = context.read<ArticlePageProvider>();
        provider.setContentReady();
        // Listen for full-text failure to show a snackbar.
        provider.addListener(_onProviderChanged);
        provider.checkAutoFullText(context.read<SubscriptionProvider>());
      }
    });
  }

  @override
  void dispose() {
    // Remove listener safely — provider may already be disposed if the
    // ChangeNotifierProvider was unmounted first.
    try {
      context.read<ArticlePageProvider>().removeListener(_onProviderChanged);
    } catch (_) {
      // Provider already disposed — nothing to clean up.
    }
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
                  leading: _CircleBackButton(
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
                    // Full-text toggle (icon only)
                    if (widget.item.link.isNotEmpty)
                      _CircleActionButton(
                        icon: provider.fullTextActive
                            ? Icons.auto_stories_rounded
                            : Icons.short_text_rounded,
                        isActive: provider.fullTextActive,
                        onPressed: provider.isLoadingFullText
                            ? null
                            : provider.toggleFullText,
                        tooltip: provider.fullTextActive
                            ? l10n.fullTextExtraction
                            : l10n.shortTextMode,
                      ),
                    // Open in browser (icon only)
                    _CircleActionButton(
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
                                fit: BoxFit.cover,
                                memCacheWidth: 900,
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
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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

                        // Source info bar
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.rss_feed_rounded,
                                size: 16,
                                color: colorScheme.primary.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.item.siteName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!provider.isLoadingFullText) ...[
                                _ModeBadge(
                                  isFullText:
                                      provider.fullTextActive &&
                                      provider.fullTextContent != null,
                                  fullTextLabel: l10n.fullTextExtraction,
                                  shortTextLabel: l10n.shortTextMode,
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Full-text loading indicator
                        if (!provider.contentReady) ...[
                          // Lightweight placeholder while the transition
                          // animation plays — avoids blocking the first frame.
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ] else if (provider.isLoadingFullText) ...[
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    l10n.fullTextLoading,
                                    style: TextStyle(
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.5,
                                      ),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                  return _ImageCarousel(imageUrls: urls);
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
                                        memCacheWidth: 800,
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
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.85,
                                ),
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
                          minHeight: 2.5,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.primary.withValues(alpha: 0.7),
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
// Small internal widgets used by ArticleScreen
// =============================================================================

/// Circular translucent back button for the SliverAppBar.
class _CircleBackButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _CircleBackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              Icons.arrow_back_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact full-text / short-text mode badge.
class _ModeBadge extends StatelessWidget {
  final bool isFullText;
  final String fullTextLabel;
  final String shortTextLabel;

  const _ModeBadge({
    required this.isFullText,
    required this.fullTextLabel,
    required this.shortTextLabel,
  });

  @override
  Widget build(BuildContext context) {
    final color = isFullText
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.secondary;
    final label = isFullText ? fullTextLabel : shortTextLabel;
    final icon = isFullText ? Icons.article_rounded : Icons.short_text_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular translucent action button for the SliverAppBar.
///
/// Matches the visual style of [_CircleBackButton] for consistency.
/// Shows a tooltip on long-press so the icon meaning is discoverable.
class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isActive;

  const _CircleActionButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isActive ? colorScheme.primary : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.2)
              : colorScheme.surface.withValues(alpha: 0.7),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, size: 18, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Image Carousel Widget — swipeable PageView with dot indicators
// =============================================================================

class _ImageCarousel extends StatefulWidget {
  final List<String> imageUrls;
  const _ImageCarousel({required this.imageUrls});

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  int _currentPage = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageCount = widget.imageUrls.length;
    final screenWidth = MediaQuery.of(context).size.width - 40;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        children: [
          // Swipeable image area
          SizedBox(
            height: screenWidth * 0.65,
            child: PageView.builder(
              controller: _pageController,
              itemCount: imageCount,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
              },
              itemBuilder: (context, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: widget.imageUrls[index],
                    memCacheWidth: 800,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorWidget: (context, url, error) => Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.05),
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined, size: 40),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // Dot indicators + counter
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ...List.generate(imageCount, (index) {
                final isActive = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
              const SizedBox(width: 8),
              Text(
                '${_currentPage + 1} / $imageCount',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
