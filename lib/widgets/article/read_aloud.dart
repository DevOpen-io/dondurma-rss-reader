import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_item.dart';
import '../../providers/subscription_provider.dart';
import '../../services/article_speech.dart';
import '../../theme/app_theme.dart';
import '../../services/speech_language.dart';
import '../adaptive_dialog.dart';

/// Starts or resumes reading [item] in its feed's chosen language, else
/// the one detected from its text, else the app's.
Future<void> _play(BuildContext context, FeedItem item, String html) =>
    ArticleSpeech.instance.play(
      item,
      html,
      failureMessage: AppLocalizations.of(context).readAloudFailed,
      language: context.read<SubscriptionProvider?>()?.speechLanguageFor(
        item.feedUrl,
      ),
      fallbackLanguage: Localizations.localeOf(context).languageCode,
    );

/// Starts or stops reading [item] aloud; [html] is read at press time, so
/// the full text is spoken once it has loaded.
class ReadAloudButton extends StatelessWidget {
  final FeedItem item;
  final String Function() html;

  const ReadAloudButton({super.key, required this.item, required this.html});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final speech = ArticleSpeech.instance;
    return ListenableBuilder(
      listenable: speech,
      builder: (context, _) {
        final active = speech.stateFor(item) != SpeechState.idle;
        final cs = Theme.of(context).colorScheme;
        return IconButton(
          // Matches the 48dp reading-mode track beside it; filled with the
          // theme color while reading.
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: active ? cs.primary : cs.surfaceContainerHigh,
            foregroundColor: active
                ? cs.onPrimary
                : AppThemeBuilder.readableAccent(
                    cs.primary,
                    background: cs.surfaceContainerHigh,
                    fallback: cs.onSurface,
                    minContrast: 3,
                  ),
          ),
          icon: Icon(active ? Icons.stop_rounded : Icons.headphones_rounded),
          tooltip: active ? l10n.stopReading : l10n.readAloud,
          onPressed: () =>
              unawaited(active ? speech.stop() : _play(context, item, html())),
        );
      },
    );
  }
}

/// Floating pause/resume and stop controls, shown while [item] is read.
class ReadAloudControls extends StatelessWidget {
  final FeedItem item;
  final String Function() html;

  const ReadAloudControls({super.key, required this.item, required this.html});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final speech = ArticleSpeech.instance;
    return ListenableBuilder(
      listenable: speech,
      builder: (context, _) {
        final state = speech.stateFor(item);
        if (state == SpeechState.idle) return const SizedBox.shrink();
        final playing = state == SpeechState.playing;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            elevation: 3,
            color: cs.surfaceContainerHigh,
            shape: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filled(
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    tooltip: playing ? l10n.pauseReading : l10n.resumeReading,
                    onPressed: () => unawaited(
                      playing ? speech.pause() : _play(context, item, html()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      l10n.readingAloud,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _LanguagePill(item: item),
                  IconButton(
                    icon: const Icon(Icons.stop_rounded),
                    tooltip: l10n.stopReading,
                    onPressed: () => unawaited(speech.stop()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The language the article is read in, as a short code; it opens the
/// language picker.
class _LanguagePill extends StatelessWidget {
  final FeedItem item;

  const _LanguagePill({required this.item});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final language = ArticleSpeech.instance.language;
    return Tooltip(
      message: language == null
          ? l10n.readingLanguage
          : l10n.readingLanguageCurrent(languageName(language)),
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: cs.primary,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        onPressed: () => unawaited(_pickLanguage(context, item)),
        child: language == null
            ? const Icon(Icons.translate_rounded, size: 20)
            : Text(language.toUpperCase()),
      ),
    );
  }
}

/// The languages the most common feeds are in, offered when the engine
/// cannot list its own.
const _commonLanguages = [
  'en', 'tr', 'es', 'de', 'fr', 'it', 'pt', 'nl', 'ru', 'ar', //
];

/// Picks the language [item] is read in and keeps it for its feed.
Future<void> _pickLanguage(BuildContext context, FeedItem item) async {
  final speech = ArticleSpeech.instance;
  final subscriptions = context.read<SubscriptionProvider?>();
  final offered = await speech.languages();
  if (!context.mounted) return;
  final chosen = speech.chosenLanguage;
  final codes = offered.isEmpty
      ? [..._commonLanguages]
      : offeredLanguages(
          offered,
          // The article's language and the app's lead the list.
          first: [
            ?speech.automaticLanguage,
            Localizations.localeOf(context).languageCode,
          ],
        );
  if (chosen != null && !codes.contains(chosen)) codes.insert(0, chosen);
  await showAdaptiveSheet<void>(
    context,
    _LanguageSheet(
      languages: codes,
      chosen: chosen,
      detected: speech.automaticLanguage,
      onPicked: (code) {
        unawaited(subscriptions?.setSpeechLanguage(item.feedUrl, code));
        unawaited(speech.chooseLanguage(code));
      },
    ),
  );
}

class _LanguageSheet extends StatelessWidget {
  final List<String> languages;
  final String? chosen;
  final String? detected;
  final ValueChanged<String?> onPicked;

  const _LanguageSheet({
    required this.languages,
    required this.chosen,
    required this.detected,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget option(String title, String? code, {String? subtitle}) {
      final selected = code == chosen;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        selected: selected,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            color: selected ? cs.primary : cs.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: selected
            ? Icon(Icons.check_rounded, size: 20, color: cs.primary)
            : null,
        onTap: () {
          Navigator.of(context).pop();
          onPicked(code);
        },
      );
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.readingLanguage,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                option(
                  l10n.readingLanguageAutomatic,
                  null,
                  subtitle: detected == null
                      ? null
                      : l10n.readingLanguageDetected(languageName(detected!)),
                ),
                Divider(
                  height: 1,
                  indent: 24,
                  endIndent: 24,
                  color: cs.outline.withValues(alpha: 0.2),
                ),
                for (final code in languages) option(languageName(code), code),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The article's end spacing, taller while [item] is read so the floating
/// bar does not cover the last button.
class ReadAloudSpacer extends StatelessWidget {
  final FeedItem item;

  const ReadAloudSpacer({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final speech = ArticleSpeech.instance;
    return ListenableBuilder(
      listenable: speech,
      builder: (context, _) => SizedBox(
        height: speech.stateFor(item) == SpeechState.idle ? 40 : 112,
      ),
    );
  }
}
