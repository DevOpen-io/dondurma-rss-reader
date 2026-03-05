import 'package:flutter/foundation.dart'
    show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:adblocker_webview/adblocker_webview.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../l10n/app_localizations.dart';

/// Returns `true` when the current platform supports WebView.
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

/// Modern Chrome User-Agent to avoid YouTube / Google rejecting the WebView.
const _kBrowserUserAgent =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/122.0.0.0 Mobile Safari/537.36';

/// A full-screen in-app browser page built on WebView.
///
/// Features:
/// - Linear progress indicator while the page is loading
/// - AppBar with the current page title (falls back to the initial URL host)
/// - Back / Forward / Refresh navigation controls in the bottom bar
/// - "Open in External Browser" action in the AppBar
/// - "Close" button to pop back to the article screen
/// - Ad blocking via `adblocker_webview` package when enabled
///
/// When [adBlockEnabled] is `true`, the browser uses [AdBlockerWebview] which
/// leverages EasyList and AdGuard filter lists for comprehensive ad blocking.
/// When `false`, the standard [WebViewWidget] is used without any blocking.
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
  /// Standard WebView controller — used only when ad blocking is disabled.
  WebViewController? _standardController;

  /// Ad blocker controller — used only when ad blocking is enabled.
  AdBlockerWebviewController get _adBlockController =>
      AdBlockerWebviewController.instance;

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

    // Only create the standard controller when ad blocking is disabled
    if (!widget.adBlockEnabled) {
      _initStandardController();
    }
  }

  /// Initializes the standard [WebViewController] for non-adblock mode.
  void _initStandardController() {
    _standardController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_kBrowserUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _loadingProgress = 0.0;
            });
            _refreshStandardNavState();
          },
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _loadingProgress = progress / 100.0;
            });
          },
          onPageFinished: (url) async {
            final title = await _standardController?.getTitle();
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _loadingProgress = 1.0;
              if (title != null && title.isNotEmpty) {
                _pageTitle = title;
              }
            });
            _refreshStandardNavState();
            if (context.mounted) {
              final isDark = context
                  .read<SettingsProvider>()
                  .webviewDarkModeEnabled;
              _applyDarkMode(isDark);
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

  /// Refreshes back/forward navigation state for the standard controller.
  Future<void> _refreshStandardNavState() async {
    final ctrl = _standardController;
    if (ctrl == null) return;
    final back = await ctrl.canGoBack();
    final forward = await ctrl.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  /// Refreshes back/forward navigation state for the ad blocker controller.
  Future<void> _refreshAdBlockNavState() async {
    final back = await _adBlockController.canGoBack();
    final forward = await _adBlockController.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  /// Opens the current URL in the system's default external browser.
  Future<void> _openExternal() async {
    String? currentUrl;
    if (widget.adBlockEnabled) {
      // For AdBlockerWebview, fall back to the initial URL
      currentUrl = widget.url;
    } else {
      currentUrl = await _standardController?.currentUrl() ?? widget.url;
    }
    final uri = Uri.tryParse(currentUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Handles navigation actions (back, forward, refresh) based on adblock mode.
  Future<void> _goBack() async {
    if (widget.adBlockEnabled) {
      _adBlockController.goBack();
      _refreshAdBlockNavState();
    } else {
      await _standardController?.goBack();
      _refreshStandardNavState();
    }
  }

  Future<void> _goForward() async {
    if (widget.adBlockEnabled) {
      _adBlockController.goForward();
      _refreshAdBlockNavState();
    } else {
      await _standardController?.goForward();
      _refreshStandardNavState();
    }
  }

  void _reload() {
    if (widget.adBlockEnabled) {
      _adBlockController.reload();
    } else {
      _standardController?.reload();
    }
  }

  /// Builds the body widget — either [AdBlockerWebview] or [WebViewWidget].
  Widget _buildBody() {
    if (widget.adBlockEnabled) {
      return AdBlockerWebview(
        url: Uri.parse(widget.url),
        shouldBlockAds: true,
        userAgent: _kBrowserUserAgent,
        adBlockerWebviewController: _adBlockController,
        onLoadStart: (url) {
          if (!mounted) return;
          setState(() {
            _isLoading = true;
            _loadingProgress = 0.0;
          });
          _refreshAdBlockNavState();
        },
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _loadingProgress = progress / 100.0;
          });
        },
        onLoadFinished: (url) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _loadingProgress = 1.0;
            // Update title from URL host if available
            if (url != null) {
              final uri = Uri.tryParse(url);
              if (uri != null && uri.host.isNotEmpty) {
                _pageTitle = uri.host;
              }
            }
          });
          _refreshAdBlockNavState();
          if (context.mounted) {
            final isDark = context
                .read<SettingsProvider>()
                .webviewDarkModeEnabled;
            _applyDarkMode(isDark);
          }
        },
        onLoadError: (url, code) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
          });
        },
      );
    } else {
      return WebViewWidget(controller: _standardController!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = context.watch<SettingsProvider>().webviewDarkModeEnabled;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.close,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
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
      body: _buildBody(),
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
                      await _goBack();
                    }
                  : null,
            ),
            // Forward
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 20),
              tooltip: l10n.forward,
              onPressed: _canGoForward
                  ? () async {
                      await _goForward();
                    }
                  : null,
            ),
            // Refresh
            IconButton(
              icon: const Icon(Icons.refresh, size: 22),
              tooltip: l10n.refresh,
              onPressed: _reload,
            ),
            // Dark Mode toggle
            IconButton(
              icon: Icon(
                isDarkMode ? Icons.light_mode : Icons.dark_mode,
                size: 22,
              ),
              tooltip: isDarkMode
                  ? l10n.themeLightClassic
                  : l10n.themeDarkClassic,
              onPressed: () {
                final newValue = !isDarkMode;
                context.read<SettingsProvider>().setWebviewDarkModeEnabled(
                  newValue,
                );
                _applyDarkMode(newValue);
              },
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

  /// Injects JavaScript to enable or disable DarkReader.
  Future<void> _applyDarkMode(bool enable) async {
    const String darkReaderCheck = 'typeof DarkReader !== "undefined"';

    try {
      // Execute the script on the appropriate controller
      Future<void> run(String js) async {
        if (widget.adBlockEnabled) {
          await _adBlockController.runScript(js);
        } else {
          await _standardController?.runJavaScript(js);
        }
      }

      Future<bool> isDarkReaderLoaded() async {
        try {
          if (widget.adBlockEnabled) {
            // runScript returning value is not guaranteed, but let's try
            // AdBlockerWebviewController.runScript returns Future<void>
            // We cannot evaluate. We will just inject it anyway if not enabled?
            // Actually, we can just inject and enable. DarkReader is safe to evaluate multiple times if we just inject the JS file.
            return false;
          } else {
            final result = await _standardController
                ?.runJavaScriptReturningResult(darkReaderCheck);
            return result == true || result == 'true';
          }
        } catch (_) {
          return false;
        }
      }

      if (enable) {
        // Load DarkReader if it's not already in the page
        final loaded = await isDarkReaderLoaded();
        if (!loaded) {
          if (!mounted) return;
          final darkReaderJs = await rootBundle.loadString(
            'assets/js/darkreader.min.js',
          );
          await run(darkReaderJs);
        }

        // Enable DarkReader
        await run('''
          DarkReader.enable({
            brightness: 100,
            contrast: 100,
            sepia: 0
          });
        ''');
      } else {
        // Disable DarkReader
        await run('''
          if (typeof DarkReader !== "undefined") {
            DarkReader.disable();
          }
        ''');
      }
    } catch (e) {
      // Ignore if controller is not ready
      debugPrint('Error applying dark mode: $e');
    }
  }
}

/// Convenience function to open a URL based on the user's chosen browser mode.
///
/// - `'builtin'` — pushes the custom [InAppBrowser] WebView (with ad-block
///   and dark mode support). Falls back to external browser on unsupported
///   platforms.
/// - `'external'` — opens in the system's default browser via [url_launcher].
/// - `'system'` — opens in the system's in-app browser overlay
///   (SFSafariViewController on iOS/macOS, Chrome Custom Tabs on Android)
///   via [url_launcher] with [LaunchMode.inAppBrowserView]. Falls back to
///   external browser if the platform doesn't support it.
Future<void> openInAppBrowser(
  BuildContext context,
  String url, {
  String? title,
  bool adBlockEnabled = true,
  String browserMode = 'builtin',
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;

  switch (browserMode) {
    case 'external':
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      break;

    case 'system':
      // Use the platform's native in-app browser (SFSafariViewController /
      // Chrome Custom Tabs). Falls back to external if unsupported.
      final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      break;

    case 'builtin':
    default:
      if (_webViewSupported) {
        await Navigator.of(context, rootNavigator: true).push(
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
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      break;
  }
}
