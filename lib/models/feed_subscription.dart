import 'dart:math';

/// Represents a user's subscription to an RSS/Atom feed source.
///
/// Immutable value object that stores the feed URL, display name, category
/// folder, notification preference, full-text extraction preference, and
/// per-feed keyword exclusion list. Serializable to/from JSON for Hive
/// persistence.
class FeedSubscription {
  final String url;
  final String name;
  final String category;
  final bool notificationsEnabled;
  final bool? fullTextEnabled;
  final List<String> excludedKeywords;

  /// When not empty, only articles matching one of these rules are shown
  /// for this feed (#69).
  final List<String> onlyKeywords;
  final String notificationEpoch;

  /// Minutes between automatic fetches of this feed; null follows the app's
  /// refresh cycle (#68). A pull to refresh always fetches.
  final int? refreshIntervalMinutes;

  FeedSubscription({
    required this.url,
    required this.name,
    required this.category,
    this.notificationsEnabled = true,
    this.fullTextEnabled,
    this.excludedKeywords = const [],
    this.onlyKeywords = const [],
    String? notificationEpoch,
    this.refreshIntervalMinutes,
  }) : notificationEpoch = notificationEpoch ?? _newNotificationEpoch();

  /// Serializes this subscription to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'category': category,
    'notificationsEnabled': notificationsEnabled,
    _schemaKey: _schemaVersion,
    if (fullTextEnabled != null) 'fullTextEnabled': fullTextEnabled,
    'excludedKeywords': excludedKeywords,
    if (onlyKeywords.isNotEmpty) 'onlyKeywords': onlyKeywords,
    'notificationEpoch': notificationEpoch,
    if (refreshIntervalMinutes != null)
      'refreshIntervalMinutes': refreshIntervalMinutes,
  };

  /// Schema marker written by every tri-state-aware save.
  ///
  /// Before the tri-state migration `fullTextEnabled` was a non-nullable `bool`
  /// whose default was `false`, so a stored `false` was indistinguishable from
  /// "never touched". Records carrying this marker were written after the
  /// migration, so their `false` is an explicit "always off" and is preserved;
  /// records without it treat `false` as the legacy default and map it to
  /// `null` (follow the global setting).
  static const _schemaKey = 'fullTextSchema';
  static const _schemaVersion = 2;

  /// Deserializes a [FeedSubscription] from a JSON map.
  factory FeedSubscription.fromJson(Map<String, dynamic> json) {
    final raw = json['fullTextEnabled'];
    final bool triStateAware = json[_schemaKey] == _schemaVersion;
    final bool? fullText = switch (raw) {
      true => true,
      false => triStateAware ? false : null,
      _ => null,
    };
    return FeedSubscription(
      url: json['url'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? 'Uncategorized',
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      fullTextEnabled: fullText,
      excludedKeywords:
          (json['excludedKeywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      onlyKeywords:
          (json['onlyKeywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      notificationEpoch:
          json['notificationEpoch'] as String? ?? _legacyNotificationEpoch,
      refreshIntervalMinutes: switch (json['refreshIntervalMinutes']) {
        final int minutes when minutes > 0 => minutes,
        _ => null,
      },
    );
  }

  FeedSubscription copyWith({
    String? url,
    String? name,
    String? category,
    bool? notificationsEnabled,
    bool? fullTextEnabled,
    List<String>? excludedKeywords,
    List<String>? onlyKeywords,
    String? notificationEpoch,
  }) {
    return FeedSubscription(
      url: url ?? this.url,
      name: name ?? this.name,
      category: category ?? this.category,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      fullTextEnabled: fullTextEnabled ?? this.fullTextEnabled,
      excludedKeywords: excludedKeywords ?? this.excludedKeywords,
      onlyKeywords: onlyKeywords ?? this.onlyKeywords,
      notificationEpoch: notificationEpoch ?? this.notificationEpoch,
      refreshIntervalMinutes: refreshIntervalMinutes,
    );
  }

  FeedSubscription copyWithFullTextMode(bool? value) {
    return FeedSubscription(
      url: url,
      name: name,
      category: category,
      notificationsEnabled: notificationsEnabled,
      fullTextEnabled: value,
      excludedKeywords: excludedKeywords,
      onlyKeywords: onlyKeywords,
      notificationEpoch: notificationEpoch,
      refreshIntervalMinutes: refreshIntervalMinutes,
    );
  }

  /// [minutes] null follows the app's refresh cycle.
  FeedSubscription copyWithRefreshInterval(int? minutes) {
    return FeedSubscription(
      url: url,
      name: name,
      category: category,
      notificationsEnabled: notificationsEnabled,
      fullTextEnabled: fullTextEnabled,
      excludedKeywords: excludedKeywords,
      onlyKeywords: onlyKeywords,
      notificationEpoch: notificationEpoch,
      refreshIntervalMinutes: minutes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FeedSubscription && other.url == url;

  @override
  int get hashCode => url.hashCode;

  static const String _legacyNotificationEpoch = 'legacy-v1';
  static int _epochCounter = 0;

  static String _newNotificationEpoch() {
    final random = Random.secure().nextInt(1 << 32);
    return '${DateTime.now().microsecondsSinceEpoch}-${_epochCounter++}-$random';
  }
}

/// Whether [feedUrl] reads full text among [subscriptions]: the feed's
/// tri-state `fullTextEnabled`, where null (and an unknown feed) follows
/// [autoFullText]. The single source of this rule for every isolate.
bool effectiveFullTextFor(
  Iterable<FeedSubscription> subscriptions,
  String feedUrl, {
  required bool autoFullText,
}) {
  for (final s in subscriptions) {
    if (s.url == feedUrl) return s.fullTextEnabled ?? autoFullText;
  }
  return autoFullText;
}
