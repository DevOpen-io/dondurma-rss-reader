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

    final adBlock = context.read<SettingsProvider>().adBlockEnabled;
    openInAppBrowser(context, cleanUrl, title: title, adBlockEnabled: adBlock);
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

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // ── Collapsing AppBar with hero image ──────────────────────
          SliverAppBar(
            expandedHeight: hasHero ? 280 : 0,
            pinned: true,
            stretch: true,
            leading: _CircleBackButton(onPressed: () => Navigator.pop(context)),
            title: Text(
              widget.item.siteName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
                          errorWidget: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        // Bottom gradient for readability
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                colorScheme.surface.withValues(alpha: 0.6),
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

          // ── Article content ────────────────────────────────────────
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
                            color: colorScheme.primary.withValues(alpha: 0.12),
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
                      if (widget.item.category.isNotEmpty && dateStr.isNotEmpty)
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

                  const SizedBox(height: 16),

                  // Source info bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.4,
                      ),
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
                          color: colorScheme.primary.withValues(alpha: 0.7),
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
                        // Mode badge
                        if (!_isLoadingFullText) ...[
                          _ModeBadge(
                            isFullText:
                                _fullTextActive && _fullTextContent != null,
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
                                extensionContext.attributes['data-urls'] ?? '';
                            final urls = urlsStr
                                .split('|')
                                .where((u) => u.isNotEmpty)
                                .toList();
                            if (urls.isEmpty) return const SizedBox.shrink();
                            return _ImageCarousel(imageUrls: urls);
                          },
                        ),
                        TagExtension(
                          tagsToExtend: {"img"},
                          builder: (extensionContext) {
                            final String? src =
                                extensionContext.attributes['src'];
                            if (src == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: CachedNetworkImage(
                                  imageUrl: src,
                                  memCacheWidth: 800,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, __, ___) =>
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
                          color: colorScheme.onSurface.withValues(alpha: 0.85),
                          lineHeight: LineHeight(settings.lineSpacing),
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                        ),
                        "a": Style(
                          color: colorScheme.primary,
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
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.35,
                        ),
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
                              icon: const Icon(Icons.public_rounded, size: 18),
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
///
/// Shows an icon + text label inside a tinted pill so that
/// the purpose of the button is immediately obvious.
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
