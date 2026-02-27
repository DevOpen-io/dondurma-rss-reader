import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/feed_item.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Whether the notification plugin is available on this platform.
  bool get isSupported => _initialized;

  /// Initialize the notification plugin. Call once from main().
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
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    try {
      await _plugin.initialize(settings: initSettings);
      _initialized = true;
    } catch (e) {
      debugPrint(
        'NotificationService: init failed (platform unsupported?): $e',
      );
    }
  }

  /// Request notification permissions (Android 13+ and iOS).
  Future<bool> requestPermission() async {
    if (!_initialized) return false;

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

  /// Show a notification for newly discovered articles.
  ///
  /// [newItems] — articles not previously seen.
  /// [notificationsEnabled] — global master toggle.
  /// [digestMode] — 'instant', 'daily', 'weekly'.
  /// [quietHoursStart] / [quietHoursEnd] — hour (0-23).
  Future<void> showNewArticlesNotification({
    required List<FeedItem> newItems,
    required bool notificationsEnabled,
    required String digestMode,
    required int quietHoursStart,
    required int quietHoursEnd,
  }) async {
    if (!notificationsEnabled) return;
    if (newItems.isEmpty) return;

    // Quiet hours check
    final now = DateTime.now().hour;
    if (_isInQuietHours(now, quietHoursStart, quietHoursEnd)) return;

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
    );

    try {
      await _plugin.show(
        id: 0,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('NotificationService: failed to show notification: $e');
    }
  }

  /// Returns true if [currentHour] is inside the quiet window.
  bool _isInQuietHours(int currentHour, int start, int end) {
    if (start == end) return false; // no quiet hours
    if (start < end) {
      // e.g. 8–17
      return currentHour >= start && currentHour < end;
    } else {
      // wraps midnight, e.g. 22–7
      return currentHour >= start || currentHour < end;
    }
  }
}
