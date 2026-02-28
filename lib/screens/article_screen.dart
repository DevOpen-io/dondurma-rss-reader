import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/full_text_extraction_service.dart';
import '../widgets/in_app_browser.dart';

/// Full-screen article viewer that renders HTML content via [flutter_html].
///
/// Respects the user's display settings (font size, typeface, line spacing)
/// from [SettingsProvider]. Links open in the in-app browser.
///
/// If full-text extraction is enabled for the feed (or the user manually
/// toggles it), the screen fetches and displays the full article content
/// from the original webpage.
class ArticleScreen extends StatefulWidget {
  final FeedItem item;

  const ArticleScreen({super.key, required this.item});

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
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

  @override
  void initState() {
    super.initState();
    // Check per-feed full-text default after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoFullText();
    });
  }

  /// If the feed has full-text enabled by default, trigger extraction.
  void _checkAutoFullText() {
    final subProvider = context.read<SubscriptionProvider>();
    final sub = subProvider.subscriptions.where(
      (s) => s.url == widget.item.feedUrl,
    );
    if (sub.isNotEmpty && sub.first.fullTextEnabled) {
      _activateFullText();
    }
  }

  /// Starts full-text extraction from the original article URL.
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
        // Fall back to RSS content — deactivate full-text mode
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

  /// Deactivates full-text mode, returning to the original RSS content.
  void _deactivateFullText() {
    setState(() {
      _fullTextActive = false;
      _isLoadingFullText = false;
      _fullTextContent = null;
      _fullTextFailed = false;
    });
  }

  /// Toggles full-text mode on/off.
  void _toggleFullText() {
    if (_fullTextActive) {
      _deactivateFullText();
    } else {
      _activateFullText();
    }
  }

  /// Opens [url] in the in-app browser.
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

    openInAppBrowser(context, cleanUrl, title: title);
  }

  // ---------------------------------------------------------------------------
  // HTML pre-processing — cleans up blank space and groups consecutive images
  // into carousel markers.
  // ---------------------------------------------------------------------------

  /// Pre-processes [htmlContent] to:
  /// 1. Strip ad / sponsor / "native ad" content.
  /// 2. Remove empty block elements and empty list items.
  /// 3. Deduplicate images (and match against hero cover image).
  /// 4. Group consecutive images into carousel markers.
  String _preprocessHtml(String htmlContent) {
    final doc = html_parser.parse(htmlContent);
    final body = doc.body;
    if (body == null) return htmlContent;

    // --- Pass 1: Remove ad / promo / native-ad blocks ---
    _removeAdContent(body);

    // --- Pass 2: Remove empty block elements & empty list items ---
    _removeEmptyElements(body);

    // --- Pass 3: Deduplicate images ---
    _deduplicateImages(body);

    // --- Pass 4: Group consecutive images into carousels ---
    _groupConsecutiveImages(body);

    return body.innerHtml;
  }

  // ----------- Ad / Promo removal -----------

  /// Pattern matching text / class / id that identify ad or promo content.
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

  /// Removes elements that look like ads, sponsored blocks, or footer promos.
  void _removeAdContent(html_dom.Element parent) {
    for (final el in parent.querySelectorAll('*').toList()) {
      // Check class / id
      final cls = el.attributes['class'] ?? '';
      final id = el.attributes['id'] ?? '';
      if (_adClassPattern.hasMatch(cls) || _adClassPattern.hasMatch(id)) {
        el.remove();
        continue;
      }

      // Check direct text content for common ad phrases
      // Only for block-level containers – avoid nuking inline text
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

  /// Recursively removes empty blocks and empty list items.
  void _removeEmptyElements(html_dom.Element parent) {
    const emptyTags = {'div', 'p', 'section', 'span', 'figure', 'figcaption'};
    for (final child in parent.children.toList()) {
      _removeEmptyElements(child);

      // Remove empty block elements
      if (emptyTags.contains(child.localName) &&
          child.text.trim().isEmpty &&
          child.children.isEmpty &&
          child.getElementsByTagName('img').isEmpty) {
        child.remove();
        continue;
      }

      // Remove empty list items (<li> with no text)
      if (child.localName == 'li' &&
          child.text.trim().isEmpty &&
          child.getElementsByTagName('img').isEmpty) {
        child.remove();
        continue;
      }
    }

    // After removing empty items, remove lists that became empty
    for (final child in parent.children.toList()) {
      if ((child.localName == 'ul' || child.localName == 'ol') &&
          child.children.isEmpty) {
        child.remove();
      }
    }
  }

  // ----------- Image deduplication -----------

  /// Removes duplicate `<img>` elements (same URL) and images matching the
  /// article's hero cover image.
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
        // Remove the duplicate (or its wrapper)
        _removeImageAndWrapper(img);
      } else {
        seen.add(norm);
      }
    }
  }

  /// Strips query params and protocol to compare image URLs loosely.
  String _normalizeImageUrl(String url) {
    var u = url.split('?').first; // drop query string
    u = u.replaceFirst(RegExp(r'^https?://'), ''); // drop protocol
    // Drop common CDN size suffixes like -300x200
    u = u.replaceAll(RegExp(r'-\d+x\d+(?=\.\w+$)'), '');
    return u.toLowerCase();
  }

  /// Removes [img] and its parent if parent is a wrapper (figure / picture / a)
  /// that only contained this image.
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

  /// Scans direct children of [parent] for runs of 2+ consecutive image nodes
  /// and wraps each run in an `<img-carousel data-urls="...">` element.
  void _groupConsecutiveImages(html_dom.Element parent) {
    // Recurse into children first
    for (final child in parent.children.toList()) {
      _groupConsecutiveImages(child);
    }

    // Collect runs of consecutive image-like nodes
    final children = parent.nodes.toList();
    final runs = <List<html_dom.Node>>[];
    List<html_dom.Node> currentRun = [];

    for (final node in children) {
      if (_isImageNode(node)) {
        currentRun.add(node);
      } else {
        // Whitespace-only text nodes shouldn't break a run
        if (node is html_dom.Text && node.text.trim().isEmpty) {
          if (currentRun.isNotEmpty) currentRun.add(node);
          continue;
        }
        if (currentRun.length >= 2) runs.add(List.from(currentRun));
        currentRun = [];
      }
    }
    if (currentRun.length >= 2) runs.add(currentRun);

    // Replace each run with a carousel marker
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

  /// Returns `true` if [node] is an `<img>`, or a container wrapping an `<img>`.
  /// Now also matches `<a>` tags wrapping images (linked product photos).
  bool _isImageNode(html_dom.Node node) {
    if (node is! html_dom.Element) return false;
    if (node.localName == 'img') return true;
    if ({'figure', 'picture', 'a', 'div'}.contains(node.localName)) {
      final imgs = node.getElementsByTagName('img');
      // Only treat as "image node" if the element is image-dominated
      // (little or no text besides the image)
      if (imgs.isNotEmpty) {
        final nonImgText = node.text.trim();
        return nonImgText.length < 30; // short caption OK
      }
    }
    return false;
  }

  /// Extracts the `src` attribute from an image node or its descendants.
  String? _extractImageUrl(html_dom.Node node) {
    if (node is! html_dom.Element) return null;
    if (node.localName == 'img') return node.attributes['src'];
    final imgs = node.getElementsByTagName('img');
    if (imgs.isNotEmpty) return imgs.first.attributes['src'];
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsProvider>();
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
        break; // Uses Outfit / AppTheme default
    }

    // Decide which content to render, then pre-process
    final rawContent =
        _fullTextContent ?? widget.item.content ?? widget.item.description;
    final String displayContent = _preprocessHtml(rawContent);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.siteName, style: const TextStyle(fontSize: 16)),
        actions: [
          // Full-text toggle button
          if (widget.item.link.isNotEmpty)
            IconButton(
              icon: Icon(
                _fullTextActive ? Icons.article : Icons.article_outlined,
              ),
              onPressed: _isLoadingFullText ? null : _toggleFullText,
              tooltip: l10n.fullTextToggle,
            ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: () {
              if (widget.item.link.isNotEmpty) {
                _openUrl(context, widget.item.link, title: widget.item.title);
              }
            },
            tooltip: l10n.openInBrowser,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero cover image
            if (widget.item.imageUrl != null &&
                widget.item.imageUrl!.isNotEmpty) ...[
              CachedNetworkImage(
                imageUrl: widget.item.imageUrl!,
                width: double.infinity,
                height: 250,
                fit: BoxFit.cover,
                memCacheWidth: 800,
                errorWidget: (context, url, error) {
                  return const SizedBox.shrink();
                },
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 24.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.category.toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.item.title,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.25,
                    ),
                  ),
                  if (dateStr.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      dateStr,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Mode indicator badge (always visible)
                  if (!_isLoadingFullText) ...[
                    Builder(
                      builder: (context) {
                        final isFullText =
                            _fullTextActive && _fullTextContent != null;
                        final badgeColor = isFullText
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.secondary;
                        final badgeLabel = isFullText
                            ? l10n.fullTextExtraction
                            : l10n.shortTextMode;
                        final badgeIcon = isFullText
                            ? Icons.article
                            : Icons.short_text;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: badgeColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(badgeIcon, size: 14, color: badgeColor),
                              const SizedBox(width: 6),
                              Text(
                                badgeLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: badgeColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Full-text loading indicator
                  if (_isLoadingFullText) ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32.0),
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              l10n.fullTextLoading,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                                fontSize: 14,
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
                        // Carousel for grouped consecutive images
                        TagExtension(
                          tagsToExtend: {"img-carousel"},
                          builder: (extensionContext) {
                            final urlsStr =
                                extensionContext.attributes['data-urls'] ?? '';
                            final urls = urlsStr
                                .split('|')
                                .where((u) => u.isNotEmpty)
                                .toList();
                            if (urls.isEmpty) return const SizedBox.shrink();
                            return _ImageCarousel(imageUrls: urls);
                          },
                        ),
                        // Single images
                        TagExtension(
                          tagsToExtend: {"img"},
                          builder: (extensionContext) {
                            final String? src =
                                extensionContext.attributes['src'];
                            if (src == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12.0,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: src,
                                  memCacheWidth: 800,
                                  fit: BoxFit.contain,
                                  errorWidget: (context, url, error) =>
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
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.85),
                          lineHeight: LineHeight(settings.lineSpacing),
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                        ),
                        "a": Style(
                          color: Theme.of(context).colorScheme.primary,
                          textDecoration: TextDecoration.none,
                        ),
                        "img": Style(
                          width: Width(MediaQuery.of(context).size.width - 40),
                          margin: Margins.only(top: 12, bottom: 12),
                        ),
                        "figure": Style(
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                        ),
                        "p": Style(margin: Margins.only(bottom: 12)),
                        "br": Style(margin: Margins.zero),
                        "hr": Style(margin: Margins.only(top: 16, bottom: 16)),
                        "h1": Style(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        "h2": Style(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        "h3": Style(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        "h4": Style(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        "h5": Style(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        "h6": Style(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      },
                      onLinkTap: (url, attributes, element) {
                        if (url != null && url.isNotEmpty) {
                          _openUrl(context, url);
                        }
                      },
                    ),
                  ],

                  const SizedBox(height: 32),

                  // "Read on Original Webpage" button — opens in-app browser
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (widget.item.link.isNotEmpty) {
                          _openUrl(
                            context,
                            widget.item.link,
                            title: widget.item.title,
                          );
                        }
                      },
                      icon: const Icon(Icons.public),
                      label: Text(l10n.readOnOriginalWebpage),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
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
            height: screenWidth * 0.65, // 65% aspect ratio
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
              // Dots
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
              // Counter label
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
