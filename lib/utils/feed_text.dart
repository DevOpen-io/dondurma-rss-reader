/// Cleanup for feed-supplied excerpt text.
library;

const _readMore =
    r'(?:read more|continue reading|keep reading|'
    r'read the full (?:story|article|post))';

/// WordPress "[…]" truncation marker, raw or entity-encoded.
final _bracketEllipsis = RegExp(
  r'\s*\[\s*(?:…|\.{3}|&#8230;|&hellip;)\s*\]\s*$',
);

/// WordPress/Yoast footer: "The post X appeared first on Y."
final _postAppearedFirst = RegExp(
  r'\s*The post .{1,300}? appeared first on .{1,150}?$',
);

/// "[Read more]".
final _bracketReadMore = RegExp(
  r'\s*\[\s*' + _readMore + r'\s*(?:…|\.{3})?\s*\]\s*$',
  caseSensitive: false,
);

/// "READ MORE...", "Continue reading “Title” →": the phrase, an optional
/// short tail without a sentence end, and a link-like terminator.
final _readMoreWithTerminator = RegExp(
  r'\s*\b' + _readMore + r'\b[^.!?]{0,150}?\s*(?:\.{3}|…|→|»|›)\s*$',
  caseSensitive: false,
);

/// A bare "Read more" standing after a sentence end.
final _readMoreAfterSentence = RegExp(
  r'(?<=[.!?…:)\]"”])\s*' + _readMore + r'\s*[.:!]?\s*$',
  caseSensitive: false,
);

/// Strips trailing "read more" boilerplate from a feed excerpt: "READ
/// MORE...", "Continue reading …", "[Read more]", "The post X appeared first
/// on Y." A WordPress "[…]" becomes a plain "…". Only the end of the text is
/// touched, and only where the phrase reads as a link, not as prose.
String cleanExcerpt(String text) {
  var out = text;
  for (var i = 0; i < 4; i++) {
    final before = out;
    out = out
        .replaceFirst(_postAppearedFirst, '')
        .replaceFirst(_bracketReadMore, '')
        .replaceFirst(_readMoreWithTerminator, '')
        .replaceFirst(_readMoreAfterSentence, '')
        .replaceFirst(_bracketEllipsis, ' …');
    if (out == before) break;
  }
  return identical(out, text) ? text : out.trim();
}
