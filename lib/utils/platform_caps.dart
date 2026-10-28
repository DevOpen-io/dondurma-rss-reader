import 'package:flutter/foundation.dart';

/// Central capability map for platform-dependent features.
///
/// Keeps scattered `Platform.is*` checks out of business logic: services and
/// widgets ask a capability question instead of naming an OS. Tests can
/// exercise every branch with `debugDefaultTargetPlatformOverride`.
abstract final class PlatformCaps {
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Any desktop host: Windows, Linux, macOS.
  static bool get isDesktop => isWindows || isLinux || isMacOS;

  /// Mobile host with Workmanager and home-widget support.
  static bool get isMobile => isAndroid || isIOS;

  /// `workmanager` ships Android/iOS implementations only (the overridden
  /// `workmanager_apple` claims macOS but that path is unverified — do not
  /// rely on it). Desktop refresh uses the in-process foreground timer.
  static bool get supportsBackgroundScheduler => isAndroid || isIOS;

  /// `home_widget` registers Android/iOS implementations only.
  static bool get supportsHomeWidget => isAndroid || isIOS;

  /// `webview_flutter` has Android/iOS/macOS implementations. Windows and
  /// Linux fall back to the external browser.
  static bool get supportsEmbeddedWebView => isAndroid || isIOS || isMacOS;

  /// `adblocker_webview` targets WebView-based platforms; keep it aligned
  /// with embedded-WebView support.
  static bool get supportsAdBlockWebView => supportsEmbeddedWebView;

  /// The system share sheet exists on Android/iOS. Desktop export uses
  /// native save dialogs via `file_selector`; article "share" copies the
  /// link instead.
  static bool get supportsShareSheet => isMobile;

  /// Runtime permission prompts exist on Android 13+ and iOS/macOS. Linux
  /// and Windows notifications do not use a runtime prompt — asking there
  /// would be a no-op anyway, so only mobile + macOS request.
  static bool get usesNotificationPermissionPrompt =>
      isAndroid || isIOS || isMacOS;

  /// `getNotificationAppLaunchDetails` is implemented by the Android and
  /// Darwin (iOS/macOS) notification plugins only; the Linux and Windows
  /// federated implementations throw `UnimplementedError`.
  static bool get supportsNotificationLaunchDetails =>
      isAndroid || isIOS || isMacOS;

  /// Modifier key for desktop shortcuts.
  static bool get useMetaShortcuts => isMacOS;
}
