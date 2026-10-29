import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_item.dart';
import '../../services/article_speech.dart';

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
        return IconButton.outlined(
          // Matches the 48dp reading-mode switch beside it.
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          icon: Icon(active ? Icons.stop_rounded : Icons.volume_up_outlined),
          tooltip: active ? l10n.stopReading : l10n.readAloud,
          onPressed: () => unawaited(
            active
                ? speech.stop()
                : speech.play(
                    item,
                    html(),
                    failureMessage: l10n.readAloudFailed,
                  ),
          ),
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
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    tooltip: playing ? l10n.pauseReading : l10n.resumeReading,
                    onPressed: () => unawaited(
                      playing
                          ? speech.pause()
                          : speech.play(
                              item,
                              html(),
                              failureMessage: l10n.readAloudFailed,
                            ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      l10n.readingAloud,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
