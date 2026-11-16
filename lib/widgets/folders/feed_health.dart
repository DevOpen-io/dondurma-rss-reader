import '../../l10n/app_localizations.dart';
import '../../services/feed_refresh.dart';

/// Localized short text for a stored per-feed verdict (see
/// [feedErrorCode]); unknown values, e.g. raw messages stored by older
/// versions, read as a generic failure.
String feedHealthText(AppLocalizations l10n, String code) {
  if (code == emptyFeedCode) return l10n.feedEmpty;
  if (code.startsWith('http:')) {
    return l10n.feedErrorServer(code.substring('http:'.length));
  }
  return switch (code) {
    'network' => l10n.feedErrorNetwork,
    'gone' => l10n.feedErrorGone,
    'blocked' => l10n.feedErrorBlocked,
    'notFeed' => l10n.feedErrorNotFeed,
    'parse' => l10n.feedErrorParse,
    _ => l10n.feedErrorUnknown,
  };
}
