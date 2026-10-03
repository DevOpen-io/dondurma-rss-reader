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
