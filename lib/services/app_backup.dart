import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/feed_item.dart';
import '../models/feed_subscription.dart';
import '../providers/bookmark_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../utils/platform_caps.dart';

/// The JSON document of a whole-app backup (#65): subscriptions with their
/// folders, settings, bookmarks with the article as saved, and read marks.
/// Images are left out; restored bookmarks are prepared again by the offline
/// pipeline. Nothing secret is stored.
abstract final class AppBackup {
  static const format = 'dondurma-backup';
  static const version = 1;
}

enum BackupProblem { notABackup, tooNew }

class BackupException implements Exception {
  const BackupException(this.problem);
  final BackupProblem problem;

  @override
  String toString() => 'BackupException(${problem.name})';
}

/// How many feeds and bookmarks a restore added.
typedef RestoreSummary = ({int feeds, int bookmarks});

String exportAppBackup({
  required SettingsProvider settings,
  required SubscriptionProvider subscriptions,
  required BookmarkProvider bookmarks,
  required FeedProvider feed,
}) {
  final folders = subscriptions.folderBackup;
  return const JsonEncoder.withIndent(' ').convert({
    'format': AppBackup.format,
    'version': AppBackup.version,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'settings': settings.backupValues(),
    // A restored feed starts a new notification history, so the
    // device-local epoch stays behind.
    'subscriptions': [
      for (final sub in subscriptions.subscriptions)
        sub.toJson()..remove('notificationEpoch'),
    ],
    'customCategories': folders.custom,
    'categoryIcons': folders.icons,
    'categoryOrder': folders.order,
    'bookmarks': [for (final item in bookmarks.bookmarkedItems) item.toJson()],
    'readItems': [
      for (final (feedUrl, id) in feed.readRefs) [feedUrl, id],
    ],
  });
}

/// Restores [json] on top of the current data: feeds, folders, bookmarks
/// and read marks are added where missing, settings are replaced. The whole
/// document is validated first; a [BackupException] leaves everything as it
/// was.
Future<RestoreSummary> restoreAppBackup(
  String json, {
  required SettingsProvider settings,
  required SubscriptionProvider subscriptions,
  required BookmarkProvider bookmarks,
  required FeedProvider feed,
}) async {
  final backup = _parse(json);
  await settings.restoreBackupValues(backup.settings);
  await subscriptions.restoreFolders(
    custom: backup.customCategories,
    icons: backup.categoryIcons,
    order: backup.categoryOrder,
  );
  final feeds = await subscriptions.importFeeds(backup.subscriptions);
  final added = bookmarks.restoreBookmarks(backup.bookmarks);
  feed.restoreReadRefs(backup.readItems);
  return (feeds: feeds, bookmarks: added);
}

/// Throws the [BackupException] a restore of [json] would, without
/// changing anything.
void checkAppBackup(String json) => _parse(json);

typedef _Backup = ({
  Map<String, Object?> settings,
  List<FeedSubscription> subscriptions,
  List<String> customCategories,
  Map<String, Object?> categoryIcons,
  List<String> categoryOrder,
  List<FeedItem> bookmarks,
  List<(String, String)> readItems,
});

_Backup _parse(String json) {
  const notABackup = BackupException(BackupProblem.notABackup);
  final Object? doc;
  try {
    doc = jsonDecode(json);
  } on FormatException {
    throw notABackup;
  }
  if (doc is! Map<String, dynamic> || doc['format'] != AppBackup.format) {
    throw notABackup;
  }
  final Map<String, dynamic> map = doc;
  final version = map['version'];
  if (version is! int) throw notABackup;
  if (version > AppBackup.version) {
    throw const BackupException(BackupProblem.tooNew);
  }
  try {
    List<dynamic> list(String key) => map[key] as List<dynamic>? ?? const [];
    return (
      settings: map['settings'] as Map<String, dynamic>? ?? const {},
      subscriptions: [
        for (final raw in list('subscriptions'))
          _subscription(raw as Map<String, dynamic>),
      ],
      customCategories: list('customCategories').cast<String>().toList(),
      categoryIcons: map['categoryIcons'] as Map<String, dynamic>? ?? const {},
      categoryOrder: list('categoryOrder').cast<String>().toList(),
      bookmarks: [
        for (final raw in list('bookmarks'))
          _bookmark(raw as Map<String, dynamic>),
      ],
      readItems: [
        for (final raw in list('readItems'))
          if (raw case [final String feedUrl, final String id]) (feedUrl, id),
      ],
    );
  } on BackupException {
    rethrow;
  } catch (_) {
    // Wrong types anywhere (a cast or a missing required field).
    throw notABackup;
  }
}

FeedSubscription _subscription(Map<String, dynamic> json) {
  final parsed = FeedSubscription.fromJson(json);
  final uri = Uri.tryParse(parsed.url);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw const BackupException(BackupProblem.notABackup);
  }
  // A fresh notification epoch: the first fetch initializes silently.
  return FeedSubscription(
    url: parsed.url,
    name: parsed.name,
    category: parsed.category,
    notificationsEnabled: parsed.notificationsEnabled,
    fullTextEnabled: parsed.fullTextEnabled,
    excludedKeywords: parsed.excludedKeywords,
  );
}

FeedItem _bookmark(Map<String, dynamic> json) {
  final item = FeedItem.fromJson(json);
  if (item.id.isEmpty || item.feedUrl.isEmpty) {
    throw const BackupException(BackupProblem.notABackup);
  }
  return item;
}

/// Saves a backup file: the native save dialog on desktop, the share sheet
/// on mobile (as OPML export does). Returns `true` on success or when the
/// user cancels, `false` on an error.
Future<bool> saveBackupFile(String json) async {
  final date = DateTime.now().toIso8601String().substring(0, 10);
  final name = 'dondurma-backup-$date.json';
  try {
    if (!PlatformCaps.supportsShareSheet) {
      final location = await getSaveLocation(
        acceptedTypeGroups: [_backupTypeGroup],
        suggestedName: name,
      );
      if (location == null) return true;
      var path = location.path;
      if (!path.toLowerCase().endsWith('.json')) path = '$path.json';
      await File(path).writeAsString(json, flush: true);
      return true;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(json, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'application/json')]),
    );
    return result.status == ShareResultStatus.success ||
        result.status == ShareResultStatus.dismissed;
  } catch (_) {
    return false;
  }
}

/// Lets the user pick a backup file and returns its text, or null when they
/// cancel.
Future<String?> pickBackupFile() async {
  final file = await openFile(acceptedTypeGroups: [_backupTypeGroup]);
  return file?.readAsString();
}

const _backupTypeGroup = XTypeGroup(
  label: 'Dondurma backup',
  extensions: ['json'],
  mimeTypes: ['application/json'],
  uniformTypeIdentifiers: ['public.json'],
);
