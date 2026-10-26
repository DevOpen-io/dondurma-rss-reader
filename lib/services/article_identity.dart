import 'dart:convert';

import '../models/feed_item.dart';

/// One source instance of an article: the canonical subscription URL plus
/// the item's normalized id. Two feeds sharing a GUID are two instances —
/// durable records, read marks and claims are keyed by this, never by the
/// bare id. [key] is a typed (JSON) encoding, not a delimiter join.
final class ArticleRef {
  ArticleRef(this.feedUrl, String id)
    : id = ArticleIdentity.normalizeItemId(id) ?? id;

  ArticleRef.of(FeedItem item) : this(item.feedUrl, item.id);

  /// Inverse of [key]; null for anything that is not an instance key.
  static ArticleRef? tryParse(String key) {
    try {
      final decoded = jsonDecode(key);
      if (decoded is List &&
          decoded.length == 2 &&
          decoded[0] is String &&
          decoded[1] is String) {
        return ArticleRef(decoded[0] as String, decoded[1] as String);
      }
    } catch (_) {}
    return null;
  }

  final String feedUrl;
  final String id;

  String get key => jsonEncode([feedUrl, id]);

  @override
  bool operator ==(Object other) =>
      other is ArticleRef && other.feedUrl == feedUrl && other.id == id;

  @override
  int get hashCode => Object.hash(feedUrl, id);

  @override
  String toString() => 'ArticleRef($feedUrl, $id)';
}

class ArticleIdentity {
  static String? nonEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Canonical form for duplicate-subscription checks: scheme/host
  /// normalization plus trailing-slash stripping (`/feed/` == `/feed`,
  /// `https://x.com/` == `https://x.com`). Article URLs intentionally keep
  /// their slashes — they feed into persisted item IDs.
  static String normalizeFeedUrl(String value) {
    final normalized = _normalizeUrl(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.path.isEmpty) return normalized;
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri.replace(path: path).toString();
  }

  static String? normalizeArticleUrl(String? value) {
    final normalized = _normalizeUrl(value ?? '');
    return normalized.isEmpty ? null : normalized;
  }

  static String? normalizeItemId(String? value) {
    final trimmed = nonEmpty(value);
    if (trimmed == null) return null;
    return normalizeArticleUrl(trimmed) ?? trimmed;
  }

  // Preserve legacy format so upgrading does not mint new fallback IDs.
  static String fallbackId(String feedUrl, String? title, String? rawDate) =>
      'gen:$feedUrl#${title ?? ''}#${rawDate ?? ''}';

  /// Cleans a feed-supplied site title for display. Google News search feeds
  /// arrive as `"site:ft.com (oil OR gas) when:1d" - Google News` — the quoted
  /// query prefix is noise, so keep only the suffix. A fully quoted title
  /// (`"Quoted Title"`) unwraps to its inner text.
  static String sanitizeSiteTitle(String title) {
    final trimmed = title.trim();
    final queryPrefix = RegExp(r'^".*?"\s*-\s*(.+)$').firstMatch(trimmed);
    if (queryPrefix != null) return queryPrefix.group(1)!.trim();
    if (trimmed.length > 2 &&
        trimmed.startsWith('"') &&
        trimmed.endsWith('"')) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  static String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme.toLowerCase() != 'http' &&
            uri.scheme.toLowerCase() != 'https') ||
        uri.host.isEmpty) {
      return trimmed;
    }

    final scheme = uri.scheme.toLowerCase();
    final hasNonDefaultPort =
        uri.hasPort &&
        !((scheme == 'http' && uri.port == 80) ||
            (scheme == 'https' && uri.port == 443));
    return Uri(
      scheme: scheme,
      userInfo: uri.userInfo,
      host: uri.host.toLowerCase(),
      port: hasNonDefaultPort ? uri.port : null,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }
}
