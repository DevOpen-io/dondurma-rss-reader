import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A full-screen in-app browser page built on [WebView].
///
/// Features:
/// - Linear progress indicator while the page is loading
/// - AppBar with the current page title (falls back to the initial URL host)
/// - Back / Forward / Refresh navigation controls in the bottom bar
/// - "Open in External Browser" action in the AppBar
/// - "Close" button to pop back to the article screen
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

  const InAppBrowser({super.key, required this.url, this.title});

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
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _loadingProgress = 0.0;
            });
            _refreshNavState();
          },
          onProgress: (progress) {
            setState(() {
              _loadingProgress = progress / 100.0;
            });
          },
          onPageFinished: (url) async {
            final title = await _controller.getTitle();
            setState(() {
              _isLoading = false;
              _loadingProgress = 1.0;
              if (title != null && title.isNotEmpty) {
                _pageTitle = title;
              }
            });
            _refreshNavState();
          },
          onWebResourceError: (error) {
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
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
            tooltip: 'Open in External Browser',
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
              tooltip: 'Back',
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
              tooltip: 'Forward',
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
              tooltip: 'Refresh',
              onPressed: () => _controller.reload(),
            ),
            // Share / Open external
            IconButton(
              icon: const Icon(Icons.ios_share, size: 22),
              tooltip: 'Open in External Browser',
              onPressed: _openExternal,
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience function to push [InAppBrowser] as a full-screen route.
Future<void> openInAppBrowser(
  BuildContext context,
  String url, {
  String? title,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => InAppBrowser(url: url, title: title),
      fullscreenDialog: true,
    ),
  );
}
