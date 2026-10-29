/// Which language an article is read aloud in: a small guess from its text
/// (script, then common words), and the engine voice that speaks it.
library;

/// Native names for the picker; any other language shows its code.
const _nativeNames = {
  'ar': 'العربية',
  'bg': 'Български',
  'ca': 'Català',
  'cs': 'Čeština',
  'da': 'Dansk',
  'de': 'Deutsch',
  'el': 'Ελληνικά',
  'en': 'English',
  'es': 'Español',
  'fa': 'فارسی',
  'fi': 'Suomi',
  'fr': 'Français',
  'he': 'עברית',
  'hi': 'हिन्दी',
  'hr': 'Hrvatski',
  'hu': 'Magyar',
  'id': 'Bahasa Indonesia',
  'it': 'Italiano',
  'ja': '日本語',
  'ko': '한국어',
  'ms': 'Bahasa Melayu',
  'nb': 'Norsk bokmål',
  'nl': 'Nederlands',
  'no': 'Norsk',
  'pl': 'Polski',
  'pt': 'Português',
  'ro': 'Română',
  'ru': 'Русский',
  'sk': 'Slovenčina',
  'sr': 'Српски',
  'sv': 'Svenska',
  'th': 'ไทย',
  'tr': 'Türkçe',
  'uk': 'Українська',
  'vi': 'Tiếng Việt',
  'zh': '中文',
};

/// The language's own name, or its code when unknown.
String languageName(String code) => _nativeNames[code] ?? code.toUpperCase();

/// The primary subtag of a BCP-47 tag (`tr` of `tr-TR`, `tr_TR`).
String _primary(String tag) => tag.split(RegExp('[-_]')).first.toLowerCase();

/// The regions voices of a language usually come in first; others use the
/// region named like the language (`tr-TR`).
const _mainRegions = {
  'ar': 'sa',
  'cs': 'cz',
  'da': 'dk',
  'el': 'gr',
  'en': 'us',
  'he': 'il',
  'hi': 'in',
  'ja': 'jp',
  'ko': 'kr',
  'nb': 'no',
  'pt': 'br',
  'sv': 'se',
  'uk': 'ua',
  'zh': 'cn',
};

/// The engine tag that speaks [code] among [offered] (the engine's
/// languages): the language's main region, else any of its regions. Null
/// when the engine lacks it; the bare code when the offer is unknown.
String? resolveSpeechTag(String code, List<String> offered) {
  if (offered.isEmpty) return code;
  final matches = offered.where((tag) => _primary(tag) == code).toList();
  if (matches.isEmpty) return null;
  final main = '$code-${_mainRegions[code] ?? code}';
  for (final tag in matches) {
    if (tag.toLowerCase().replaceAll('_', '-') == main) return tag;
  }
  for (final tag in matches) {
    if (tag.toLowerCase() == code) return tag;
  }
  return matches.first;
}

/// The languages of the engine's [offered] tags, one each, by native name.
List<String> offeredLanguages(List<String> offered) =>
    {for (final tag in offered) _primary(tag)}.toList()
      ..sort((a, b) => languageName(a).compareTo(languageName(b)));

/// Words common in one Latin-script language and rare in the others; words
/// shared across them ("de", "a", "en", "que") are left out.
const _commonWords = <String, Set<String>>{
  'en': {
    'the', 'of', 'and', 'to', 'is', 'that', 'for', 'with', 'was', 'on', //
    'it', 'are', 'has', 'have', 'be', 'by', 'this', 'from', 'at', 'will',
    'which', 'an', 'or', 'not', 'but', 'they', 'their', 'its', 'said',
    'been', 'more', 'than', 'who', 'we', 'you', 'he', 'she', 'his', 'her',
  },
  'tr': {
    've', 'bir', 'bu', 'için', 'icin', 'ile', 'olarak', 'olan', 'çok', //
    'cok', 'daha', 'gibi', 'ama', 'değil', 'degil', 'sonra', 'kadar', 'her',
    'ise', 'şu', 'ki', 'mi', 'yeni', 'oldu', 'olduğu', 'oldugu', 'göre',
    'gore', 'ancak', 'veya', 'diye', 'tarafından', 'tarafindan',
  },
  'es': {
    'el', 'los', 'las', 'y', 'una', 'por', 'del', 'con', 'para', 'como', //
    'más', 'pero', 'según', 'está', 'sus', 'al', 'muy', 'también', 'entre',
    'ya', 'fue', 'han', 'esta', 'este', 'hay', 'sin',
  },
  'pt': {
    'não', 'uma', 'os', 'dos', 'das', 'com', 'é', 'do', 'da', 'na', 'em', //
    'ao', 'aos', 'mais', 'mas', 'foi', 'pelo', 'pela', 'já', 'também',
    'seu', 'sua', 'num', 'numa', 'à', 'às', 'o', 'são', 'está', 'isso',
  },
  'it': {
    'il', 'di', 'che', 'è', 'non', 'per', 'sono', 'gli', 'della', 'dei', //
    'delle', 'nel', 'nella', 'alla', 'anche', 'più', 'questo', 'questa',
    'dal', 'dalla', 'già', 'essere', 'molto', 'ed', 'ma', 'ha', 'hanno',
  },
  'fr': {
    'le', 'les', 'et', 'des', 'est', 'dans', 'pour', 'qui', 'du', 'au', //
    'aux', 'sur', 'pas', 'plus', 'ce', 'cette', 'sont', 'avec', 'ont',
    'été', 'mais', 'ou', 'leur', 'très', 'déjà', 'nous', 'vous', 'elle',
    'qu', 'une',
  },
  'nl': {
    'het', 'een', 'van', 'dat', 'niet', 'op', 'zijn', 'met', 'voor', //
    'deze', 'ook', 'maar', 'aan', 'bij', 'nog', 'wordt', 'worden', 'heeft',
    'hebben', 'ze', 'er', 'om', 'naar', 'wat', 'door', 'uit', 'dan', 'al',
  },
  'de': {
    'der', 'die', 'das', 'und', 'ist', 'nicht', 'mit', 'zu', 'den', 'dem', //
    'ein', 'eine', 'einen', 'sich', 'auf', 'auch', 'für', 'sie', 'es',
    'im', 'wird', 'werden', 'hat', 'dass', 'nach', 'wie', 'aus', 'bei',
    'oder', 'sind', 'noch', 'als',
  },
};

/// Letters only one of the languages above uses.
const _telltaleLetters = {
  'ğ': 'tr', 'ş': 'tr', 'ı': 'tr', //
  'ß': 'de', 'ñ': 'es', 'ã': 'pt', 'õ': 'pt', 'œ': 'fr',
};

/// The language of a non-Latin letter, by its script; Han is Chinese
/// unless kana show up beside it.
String? _scriptOf(int rune) {
  if (rune >= 0x0400 && rune <= 0x04FF) return 'ru';
  if (rune >= 0x0600 && rune <= 0x06FF) return 'ar';
  if (rune >= 0x0370 && rune <= 0x03FF) return 'el';
  if (rune >= 0x0590 && rune <= 0x05FF) return 'he';
  if (rune >= 0x0900 && rune <= 0x097F) return 'hi';
  if (rune >= 0x0E00 && rune <= 0x0E7F) return 'th';
  if (rune >= 0x3040 && rune <= 0x30FF) return 'ja';
  if (rune >= 0xAC00 && rune <= 0xD7AF) return 'ko';
  if (rune >= 0x4E00 && rune <= 0x9FFF) return 'zh';
  return null;
}

/// The language [text] is most likely in, as a language code, or null when
/// it is too short or too mixed to tell.
String? detectLanguage(String text) {
  // 'İ'.toLowerCase() is "i̇" (with a combining dot) and misses "için".
  final lower = text.replaceAll('İ', 'i').toLowerCase();

  final scripts = <String, int>{};
  var latin = 0;
  for (final rune in lower.runes) {
    final script = _scriptOf(rune);
    if (script != null) {
      scripts[script] = (scripts[script] ?? 0) + 1;
    } else if ((rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0xC0 && rune <= 0x24F)) {
      latin++;
    }
  }
  if (scripts.isNotEmpty) {
    final (script, count) = scripts.entries
        .map((e) => (e.key, e.value))
        .reduce((a, b) => a.$2 >= b.$2 ? a : b);
    if (count > latin && count >= 4) {
      return script == 'zh' && (scripts['ja'] ?? 0) > 0 ? 'ja' : script;
    }
  }

  final words = lower
      .split(RegExp(r"[^\p{L}]+", unicode: true))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.length < 4) return null;
  final scores = {for (final language in _commonWords.keys) language: 0};
  for (final word in words) {
    for (final MapEntry(key: language, value: common) in _commonWords.entries) {
      if (common.contains(word)) scores[language] = scores[language]! + 1;
    }
  }
  for (final rune in lower.runes) {
    final language = _telltaleLetters[String.fromCharCode(rune)];
    if (language != null) scores[language] = scores[language]! + 1;
  }
  final ranked = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final best = ranked.first;
  if (best.value < 2 || best.value == ranked[1].value) return null;
  return best.key;
}
