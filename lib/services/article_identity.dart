class ArticleIdentity {
  static String? nonEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static String normalizeFeedUrl(String value) => _normalizeUrl(value);

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
