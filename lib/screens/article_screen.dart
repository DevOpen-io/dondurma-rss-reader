import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/full_text_extraction_service.dart';
import '../widgets/in_app_browser.dart';

/// Full-screen article viewer with swipe navigation between articles.
///
/// Wraps individual article pages in a [PageView] so users can swipe
/// left/right to navigate between articles. Each page independently
/// manages its own scroll state, full-text extraction, and reading progress.
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
        return _ArticlePage(
          item: widget.items[index],
          currentIndex: index,
          totalCount: widget.items.length,
          isActive: index == _currentIndex,
        );
      },
    );
  }
}

// =============================================================================
// Individual article page — self-contained with its own scroll, full-text,
// reading progress, and estimated reading time.
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
  final FullTextExtractionService _extractionService =
      FullTextExtractionService();

  /// Whether full-text mode is active (either via per-feed default or manual).
  bool _fullTextActive = false;

  /// Whether a full-text fetch is currently in progress.
  bool _isLoadingFullText = false;

  /// The extracted full-text HTML, if successfully fetched.
  String? _fullTextContent;

  /// Whether the extraction was attempted and failed.
  bool _fullTextFailed = false;

  /// Reading progress (0.0 to 1.0).
  final ValueNotifier<double> _readingProgress = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoFullText();
    });
  }

  @override
  void dispose() {
    _readingProgress.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Full-text extraction
  // ---------------------------------------------------------------------------

  void _checkAutoFullText() {
    final subProvider = context.read<SubscriptionProvider>();
    final sub = subProvider.subscriptions.where(
      (s) => s.url == widget.item.feedUrl,
    );
    if (sub.isNotEmpty && sub.first.fullTextEnabled) {
      _activateFullText();
    }
  }

  Future<void> _activateFullText() async {
    if (widget.item.link.isEmpty) return;

    setState(() {
      _fullTextActive = true;
      _isLoadingFullText = true;
      _fullTextFailed = false;
      _fullTextContent = null;
    });

    final result = await _extractionService.extractFullText(widget.item.link);

    if (!mounted) return;

    setState(() {
      _isLoadingFullText = false;
      if (result != null && result.isNotEmpty) {
        _fullTextContent = result;
        _fullTextFailed = false;
      } else {
        _fullTextFailed = true;
        _fullTextActive = false;
        _fullTextContent = null;
      }
    });

    if (_fullTextFailed && mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.fullTextFailed)));
    }
  }

  void _deactivateFullText() {
    setState(() {
      _fullTextActive = false;
      _isLoadingFullText = false;
      _fullTextContent = null;
      _fullTextFailed = false;
    });
  }

  void _toggleFullText() {
    if (_fullTextActive) {
      _deactivateFullText();
    } else {
      _activateFullText();
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
  // Estimated reading time
  // ---------------------------------------------------------------------------

  /// Strips HTML tags and counts words to estimate reading time.
  int _estimateReadingMinutes(String htmlContent) {
    final doc = html_parser.parse(htmlContent);
    final text = doc.body?.text ?? '';
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    // Average reading speed: ~200 words/minute
    return (words / 200).ceil();
  }

  // ---------------------------------------------------------------------------
  // HTML pre-processing
  // ---------------------------------------------------------------------------

  String _preprocessHtml(String htmlContent) {
    final doc = html_parser.parse(htmlContent);
    final body = doc.body;
    if (body == null) return htmlContent;

    _removeAdContent(body);
    _removeEmptyElements(body);
    _deduplicateImages(body);
    _groupConsecutiveImages(body);

    return body.innerHtml;
  }

  // ----------- Ad / Promo removal -----------

  static final _adTextPattern = RegExp(
    r'(advertiser\s*content|native\s*ad|sponsored\s*content|'
    r'advertisement|promoted\s*content|follow\s*topics\s*and\s*authors|'
    r'read\s*our\s*recent\s*profile)',
    caseSensitive: false,
  );

  static final _adClassPattern = RegExp(
    r'(ad-|advert|sponsor|promo|native-ad|outbrain|taboola|'
    r'related-stories|rec-rail|story-rail|commerce|affiliate)',
    caseSensitive: false,
  );

  void _removeAdContent(html_dom.Element parent) {
    for (final el in parent.querySelectorAll('*').toList()) {
      final cls = el.attributes['class'] ?? '';
      final id = el.attributes['id'] ?? '';
      if (_adClassPattern.hasMatch(cls) || _adClassPattern.hasMatch(id)) {
        el.remove();
        continue;
      }

      final tag = el.localName ?? '';
      if ({
        'div',
        'section',
        'aside',
        'p',
        'span',
        'h2',
        'h3',
        'h4',
      }.contains(tag)) {
        final text = el.text.trim();
        if (text.length < 200 && _adTextPattern.hasMatch(text)) {
          el.remove();
        }
      }
    }
  }

  // ----------- Empty element removal -----------

  void _removeEmptyElements(html_dom.Element parent) {
    const emptyTags = {'div', 'p', 'section', 'span', 'figure', 'figcaption'};
    for (final child in parent.children.toList()) {
      _removeEmptyElements(child);

      if (emptyTags.contains(child.localName) &&
          child.text.trim().isEmpty &&
          child.children.isEmpty &&
          child.getElementsByTagName('img').isEmpty) {
        child.remove();
        continue;
      }

      if (child.localName == 'li' &&
          child.text.trim().isEmpty &&
          child.getElementsByTagName('img').isEmpty) {
        child.remove();
        continue;
      }
    }

    for (final child in parent.children.toList()) {
      if ((child.localName == 'ul' || child.localName == 'ol') &&
          child.children.isEmpty) {
        child.remove();
      }
    }
  }

  // ----------- Image deduplication -----------

  void _deduplicateImages(html_dom.Element parent) {
    final heroUrl = widget.item.imageUrl ?? '';
    final seen = <String>{};
    if (heroUrl.isNotEmpty) {
      seen.add(_normalizeImageUrl(heroUrl));
    }

    for (final img in parent.getElementsByTagName('img').toList()) {
      final src = img.attributes['src'] ?? '';
      if (src.isEmpty) {
        img.remove();
        continue;
      }
      final norm = _normalizeImageUrl(src);
      if (seen.contains(norm)) {
        _removeImageAndWrapper(img);
      } else {
        seen.add(norm);
      }
    }
  }

  String _normalizeImageUrl(String url) {
    var u = url.split('?').first;
    u = u.replaceFirst(RegExp(r'^https?://'), '');
    u = u.replaceAll(RegExp(r'-\d+x\d+(?=\.\w+$)'), '');
    return u.toLowerCase();
  }

  void _removeImageAndWrapper(html_dom.Element img) {
    final parent = img.parent;
    if (parent != null &&
        {'figure', 'picture', 'a'}.contains(parent.localName) &&
        parent.getElementsByTagName('img').length <= 1) {
      parent.remove();
    } else {
      img.remove();
    }
  }

  // ----------- Consecutive-image carousel grouping -----------

  void _groupConsecutiveImages(html_dom.Element parent) {
    for (final child in parent.children.toList()) {
      _groupConsecutiveImages(child);
    }

    final children = parent.nodes.toList();
    final runs = <List<html_dom.Node>>[];
    List<html_dom.Node> currentRun = [];

    for (final node in children) {
      if (_isImageNode(node)) {
        currentRun.add(node);
      } else {
        if (node is html_dom.Text && node.text.trim().isEmpty) {
          if (currentRun.isNotEmpty) currentRun.add(node);
          continue;
        }
        if (currentRun.length >= 2) runs.add(List.from(currentRun));
        currentRun = [];
      }
    }
    if (currentRun.length >= 2) runs.add(currentRun);

    for (final run in runs) {
      final urls = <String>[];
      for (final node in run) {
        final url = _extractImageUrl(node);
        if (url != null && url.isNotEmpty) urls.add(url);
      }
      if (urls.length < 2) continue;

      final carousel = html_dom.Element.tag('img-carousel')
        ..attributes['data-urls'] = urls.join('|');

      run.first.replaceWith(carousel);
      for (int i = 1; i < run.length; i++) {
        run[i].remove();
      }
    }
  }

  bool _isImageNode(html_dom.Node node) {
    if (node is! html_dom.Element) return false;
    if (node.localName == 'img') return true;
    if ({'figure', 'picture', 'a', 'div'}.contains(node.localName)) {
      final imgs = node.getElementsByTagName('img');
      if (imgs.isNotEmpty) {
        final nonImgText = node.text.trim();
        return nonImgText.length < 30;
      }
    }
    return false;
  }

  String? _extractImageUrl(html_dom.Node node) {
    if (node is! html_dom.Element) return null;
    if (node.localName == 'img') return node.attributes['src'];
    final imgs = node.getElementsByTagName('img');
    if (imgs.isNotEmpty) return imgs.first.attributes['src'];
    return null;
  }

  // ---------------------------------------------------------------------------
  // Scroll tracking for reading progress
  // ---------------------------------------------------------------------------

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      if (metrics.maxScrollExtent > 0) {
        _readingProgress.value = (metrics.pixels / metrics.maxScrollExtent)
            .clamp(0.0, 1.0);
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsProvider>();
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

    // Decide which content to render, then pre-process
    final rawContent =
        _fullTextContent ?? widget.item.content ?? widget.item.description;
    final String displayContent = _preprocessHtml(rawContent);
    final hasHero =
        widget.item.imageUrl != null && widget.item.imageUrl!.isNotEmpty;

    // Estimated reading time
    final readingMinutes = _estimateReadingMinutes(rawContent);
    final readTimeText = readingMinutes <= 0
        ? l10n.lessThanOneMinRead
        : l10n.estimatedReadTime(readingMinutes);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // ── Article content with scroll tracking ──────────────────────
          NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
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
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.item.siteName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Article position indicator
                      if (widget.totalCount > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            l10n.articlePosition(
                              widget.currentIndex + 1,
                              widget.totalCount,
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    if (widget.item.link.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: _AppBarChip(
                          icon: _fullTextActive
                              ? Icons.auto_stories_rounded
                              : Icons.short_text_rounded,
                          label: _fullTextActive
                              ? l10n.fullTextExtraction
                              : l10n.shortTextMode,
                          isActive: _fullTextActive,
                          onTap: _isLoadingFullText ? null : _toggleFullText,
                        ),
                      ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: _AppBarChip(
                        icon: Icons.launch_rounded,
                        label: l10n.openInBrowser,
                        onTap: widget.item.link.isNotEmpty
                            ? () => _openUrl(
                                context,
                                widget.item.link,
                                title: widget.item.title,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
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
                              if (!_isLoadingFullText) ...[
                                _ModeBadge(
                                  isFullText:
                                      _fullTextActive &&
                                      _fullTextContent != null,
                                  fullTextLabel: l10n.fullTextExtraction,
                                  shortTextLabel: l10n.shortTextMode,
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Full-text loading indicator
                        if (_isLoadingFullText) ...[
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
                valueListenable: _readingProgress,
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

/// Labeled chip-style action button for the app bar.
class _AppBarChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  const _AppBarChip({
    required this.icon,
    required this.label,
    this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return Material(
      color: isActive
          ? theme.colorScheme.primary.withValues(alpha: 0.15)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color.withValues(alpha: 0.8)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
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
