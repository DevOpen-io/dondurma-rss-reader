import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/feed_item.dart';
import '../utils/platform_caps.dart';

/// Singleton service that wraps [FlutterLocalNotificationsPlugin].
///
/// Provides initialization, permission requests, and article notification
/// delivery with support for quiet hours and digest modes.
///
/// Supported platforms: Android, iOS, macOS. On unsupported platforms
/// [isSupported] returns `false` and all operations are no-ops.
class NotificationService {
  NotificationService._();

  /// The shared singleton instance.
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Emits the notification payload (article JSON) when the user taps a
  /// notification. Listened to in `main.dart` for navigation.
  final StreamController<String> _tapController =
      StreamController<String>.broadcast();

  /// Stream of article JSON payloads from tapped notifications.
  Stream<String> get onArticleTapped => _tapController.stream;

  bool _initialized = false;

  /// Whether the notification plugin is available on this platform.
  bool get isSupported => _initialized;

  /// Initializes the notification plugin. Call once from `main()`.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );
    // Windows toast activation requires a stable AUMID + callback GUID.
    // The GUID identifies this app's notification activator — it is fixed,
    // not per-install.
    const windowsSettings = WindowsInitializationSettings(
      appName: 'Dondurma RSS Reader',
      appUserModelId: 'io.devopen.dondurma',
      guid: '9f4c2a1e-3b7d-4f8a-9c2e-5d6a1b8e3f04',
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );
    try {
      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      _initialized = true;

      // Handle the case where the app was launched by tapping a notification
      // while it was terminated. Linux/Windows plugin implementations do
      // not implement this method.
      final launchDetails = PlatformCaps.supportsNotificationLaunchDetails
          ? await _plugin.getNotificationAppLaunchDetails()
          : null;
      if (launchDetails != null &&
          launchDetails.didNotificationLaunchApp &&
          launchDetails.notificationResponse?.payload != null) {
        _onNotificationTapped(launchDetails.notificationResponse!);
      }
    } catch (e) {
      debugPrint(
        'NotificationService: init failed (platform unsupported?): $e',
      );
    }
  }

  /// Requests notification permissions on Android 13+ and iOS/macOS.
  ///
  /// Returns `true` if permission was granted, `false` otherwise. Linux and
  /// Windows notifications need no runtime prompt — returns `true` without
  /// touching the plugin.
  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    if (!PlatformCaps.usesNotificationPermissionPrompt) return true;

    try {
      // Android 13+
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? false;
      }

      // iOS
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('NotificationService: requestPermission failed: $e');
      return false;
    }

    return true;
  }

  /// Shows a notification for newly discovered articles.
  ///
  /// [newItems] — articles not previously seen.
  /// [notificationsEnabled] — global master toggle.
  /// [digestMode] — `'instant'`, `'daily'`, or `'weekly'`.
  /// [quietHoursStart] / [quietHoursEnd] — hour (0-23).
  ///
  /// No-op when notifications are disabled, the list is empty, the current
  /// time falls within quiet hours, or digest mode is not `'instant'`.
  /// Handles the user tapping on a notification.
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _tapController.add(payload);
    }
  }

  Future<void> showNewArticlesNotification({
    required List<FeedItem> newItems,
    required bool notificationsEnabled,
    required String digestMode,
    required int quietHoursStart,
    required int quietHoursEnd,
    bool quietHoursEnabled = true,
    String? latestItemJson,
  }) async {
    if (!notificationsEnabled) return;
    if (newItems.isEmpty) return;

    // Quiet hours check
    if (quietHoursEnabled) {
      final now = DateTime.now().hour;
      if (_isInQuietHours(now, quietHoursStart, quietHoursEnd)) return;
    }

    // In digest mode, we don't fire instant notifications
    if (digestMode != 'instant') return;

    final count = newItems.length;
    final latest = newItems.first;
    final title = '$count new article${count > 1 ? 's' : ''}';
    final body = '${latest.siteName}: ${latest.title}';

    const androidDetails = AndroidNotificationDetails(
      'new_articles',
      'New Articles',
      channelDescription: 'Notifications for new RSS feed articles',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      groupKey: 'com.icecream.rss.NEW_ARTICLES',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );

    try {
      await _plugin.show(
        id: 0,
        title: title,
        body: body,
        notificationDetails: details,
        payload: latestItemJson,
      );
    } catch (e) {
      debugPrint('NotificationService: failed to show notification: $e');
    }
  }

  /// Cancels every pending and shown local notification — the factory-reset
  /// boundary (#40): wiped articles must never resurface as notifications.
  Future<void> cancelAll() async {
    if (!isSupported) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('NotificationService: failed to cancel notifications: $e');
    }
  }

  static bool isInQuietHours(int currentHour, int start, int end) =>
      _isInQuietHours(currentHour, start, end);

  static bool _isInQuietHours(int currentHour, int start, int end) {
    if (start == end) return false; // no quiet hours
    if (start < end) {
      // e.g. 8–17
      return currentHour >= start && currentHour < end;
    } else {
      // wraps midnight, e.g. 22–7
      return currentHour >= start || currentHour < end;
    }
  }

  /// Releases the stream controller. Called during app teardown.
  void dispose() {
    _tapController.close();
  }
}
