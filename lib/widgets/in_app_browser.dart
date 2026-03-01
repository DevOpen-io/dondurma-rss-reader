import 'package:flutter/foundation.dart'
    show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../l10n/app_localizations.dart';
import '../services/ad_block_service.dart';

/// Returns `true` when the current platform supports [WebViewWidget].
///
/// `webview_flutter` v4.x ships native implementations for Android, iOS, and
/// macOS. On Web, Windows, and Linux there is no native WebView — we fall back
/// to [url_launcher] instead.
bool get _webViewSupported {
  if (kIsWeb) return false;
  final platform = defaultTargetPlatform;
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS;
}

/// A full-screen in-app browser page built on [WebView].
///
/// Features:
/// - Linear progress indicator while the page is loading
/// - AppBar with the current page title (falls back to the initial URL host)
/// - Back / Forward / Refresh navigation controls in the bottom bar
/// - "Open in External Browser" action in the AppBar
/// - "Close" button to pop back to the article screen
/// - Built-in ad blocker (domain blocking + element hiding)
///
/// Usage:
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute(
///     builder: (_) => InAppBrowser(url: 'https://example.com/article'),
///   ),
/// );
/// ```
class InAppBrowser extends StatefulWidget {
  final String url;
  final String? title;

  /// Whether the built-in ad blocker is active.
  final bool adBlockEnabled;

  const InAppBrowser({
    super.key,
    required this.url,
    this.title,
    this.adBlockEnabled = true,
  });

  @override
  State<InAppBrowser> createState() => _InAppBrowserState();
}

class _InAppBrowserState extends State<InAppBrowser> {
  late final WebViewController _controller;

  String _pageTitle = '';
  double _loadingProgress = 0.0;
  bool _isLoading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();

    // Derive a sensible initial title from the URL host
    _pageTitle = widget.title ?? (Uri.tryParse(widget.url)?.host ?? widget.url);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: widget.adBlockEnabled
              ? (NavigationRequest request) {
                  if (AdBlockService.shouldBlockUrl(request.url)) {
                    return NavigationDecision.prevent;
                  }
                  return NavigationDecision.navigate;
                }
              : null,
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _loadingProgress = 0.0;
            });
            _refreshNavState();
          },
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _loadingProgress = progress / 100.0;
            });
          },
          onPageFinished: (url) async {
            final title = await _controller.getTitle();
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _loadingProgress = 1.0;
              if (title != null && title.isNotEmpty) {
                _pageTitle = title;
              }
            });
            _refreshNavState();

            // Inject ad-block script after page load
            if (widget.adBlockEnabled) {
              try {
                await _controller.runJavaScript(AdBlockService.adBlockScript);
              } catch (_) {
                // Ignore errors from sandboxed frames
              }
            }
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _refreshNavState() async {
    final back = await _controller.canGoBack();
    final forward = await _controller.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  Future<void> _openExternal() async {
    final currentUrl = await _controller.currentUrl() ?? widget.url;
    final uri = Uri.tryParse(currentUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _pageTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: l10n.openInExternalBrowser,
            onPressed: _openExternal,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3.0),
          child: AnimatedOpacity(
            opacity: _isLoading ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: LinearProgressIndicator(
              value: _loadingProgress,
              minHeight: 3.0,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
      body: WebViewWidget(controller: _controller),
      bottomNavigationBar: BottomAppBar(
        height: 52,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Back
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              tooltip: l10n.back,
              onPressed: _canGoBack
                  ? () async {
                      await _controller.goBack();
                      _refreshNavState();
                    }
                  : null,
            ),
            // Forward
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 20),
              tooltip: l10n.forward,
              onPressed: _canGoForward
                  ? () async {
                      await _controller.goForward();
                      _refreshNavState();
                    }
                  : null,
            ),
            // Refresh
            IconButton(
              icon: const Icon(Icons.refresh, size: 22),
              tooltip: l10n.refresh,
              onPressed: () => _controller.reload(),
            ),
            // Share / Open external
            IconButton(
              icon: const Icon(Icons.ios_share, size: 22),
              tooltip: l10n.openInExternalBrowser,
              onPressed: _openExternal,
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience function to push [InAppBrowser] as a full-screen route.
///
/// On platforms where `webview_flutter` is not available (Windows, Linux, Web)
/// the URL is opened in the system's default external browser via
/// [url_launcher] instead.
Future<void> openInAppBrowser(
  BuildContext context,
  String url, {
  String? title,
  bool adBlockEnabled = true,
}) async {
  if (_webViewSupported) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InAppBrowser(
          url: url,
          title: title,
          adBlockEnabled: adBlockEnabled,
        ),
        fullscreenDialog: true,
      ),
    );
  } else {
    // Fallback: open in the system's external browser
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
