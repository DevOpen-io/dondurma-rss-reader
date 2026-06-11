import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import '../l10n/app_localizations.dart';

/// Language metadata used by both [LanguagePacksSheet] and
/// [ArticleTranslationSheet].
const kTranslationLanguages = <({TranslateLanguage lang, String label})>[
  (lang: TranslateLanguage.turkish, label: 'Türkçe'),
  (lang: TranslateLanguage.english, label: 'English'),
  (lang: TranslateLanguage.arabic, label: 'العربية'),
  (lang: TranslateLanguage.german, label: 'Deutsch'),
  (lang: TranslateLanguage.french, label: 'Français'),
  (lang: TranslateLanguage.spanish, label: 'Español'),
  (lang: TranslateLanguage.russian, label: 'Русский'),
  (lang: TranslateLanguage.chinese, label: '中文'),
  (lang: TranslateLanguage.japanese, label: '日本語'),
  (lang: TranslateLanguage.korean, label: '한국어'),
  (lang: TranslateLanguage.portuguese, label: 'Português'),
  (lang: TranslateLanguage.italian, label: 'Italiano'),
  (lang: TranslateLanguage.dutch, label: 'Nederlands'),
  (lang: TranslateLanguage.polish, label: 'Polski'),
  (lang: TranslateLanguage.ukrainian, label: 'Українська'),
  (lang: TranslateLanguage.hindi, label: 'हिन्दी'),
  (lang: TranslateLanguage.indonesian, label: 'Indonesia'),
  (lang: TranslateLanguage.persian, label: 'فارسی'),
];

/// Modal bottom sheet for managing on-device ML Kit translation models.
///
/// [requiredLanguages] — languages highlighted as "required" when opening
/// from a failed translation attempt so the user knows exactly what to download.
class LanguagePacksSheet extends StatefulWidget {
  final Set<TranslateLanguage> requiredLanguages;

  const LanguagePacksSheet({super.key, this.requiredLanguages = const {}});

  @override
  State<LanguagePacksSheet> createState() => _LanguagePacksSheetState();
}

class _LanguagePacksSheetState extends State<LanguagePacksSheet> {
  final _modelManager = OnDeviceTranslatorModelManager();

  /// true = downloaded, false = not downloaded, null = not yet checked.
  /// Starts as null for all; background check updates to true/false without
  /// showing a loading spinner — avoids the "everything is spinning" problem.
  final Map<TranslateLanguage, bool?> _status = {
    for (final e in kTranslationLanguages) e.lang: null,
  };

  /// Per-language simulated download progress (0.0–1.0).
  /// Only present while a download is in progress.
  final Map<TranslateLanguage, double> _progress = {};

  /// Timers that drive the simulated progress animation.
  final Map<TranslateLanguage, Timer> _progressTimers = {};

  @override
  void initState() {
    super.initState();
    // Check statuses silently in background — no per-row loading spinners.
    _checkAllStatuses();
  }

  @override
  void dispose() {
    for (final t in _progressTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _checkAllStatuses() async {
    for (final entry in kTranslationLanguages) {
      try {
        final downloaded = await _modelManager.isModelDownloaded(
          entry.lang.bcpCode,
        );
        if (mounted) setState(() => _status[entry.lang] = downloaded);
      } catch (_) {
        // Plugin unavailable (e.g. desktop) — treat as not downloaded.
        if (mounted) setState(() => _status[entry.lang] = false);
      }
    }
  }

  Future<void> _download(TranslateLanguage lang) async {
    setState(() => _progress[lang] = 0.0);

    // Simulate progress: creeps toward ~88 % using exponential ease-out.
    // When the real download completes it jumps to 100 %.
    _progressTimers[lang] = Timer.periodic(
      const Duration(milliseconds: 200),
      (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          final current = _progress[lang] ?? 0.0;
          if (current < 0.88) {
            _progress[lang] = current + (0.88 - current) * 0.04;
          }
        });
      },
    );

    try {
      await _modelManager.downloadModel(lang.bcpCode);
      _progressTimers[lang]?.cancel();
      _progressTimers.remove(lang);
      if (!mounted) return;
      // Snap to 100 %, hold briefly, then clear.
      setState(() {
        _progress[lang] = 1.0;
        _status[lang] = true;
      });
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() => _progress.remove(lang));
    } catch (_) {
      _progressTimers[lang]?.cancel();
      _progressTimers.remove(lang);
      if (mounted) {
        setState(() {
          _progress.remove(lang);
          _status[lang] = false;
        });
      }
    }
  }

  Future<void> _delete(TranslateLanguage lang) async {
    // Reuse the progress map for the brief "working" animation during delete.
    setState(() => _progress[lang] = -1.0); // sentinel = deleting
    try {
      await _modelManager.deleteModel(lang.bcpCode);
      if (mounted) setState(() => _status[lang] = false);
    } catch (_) {
      if (mounted) setState(() => _status[lang] = true);
    } finally {
      if (mounted) setState(() => _progress.remove(lang));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Fixed header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.translate_rounded,
                        size: 22,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.languagePacks,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Info banner when opened from a failed translation
                  if (widget.requiredLanguages.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.translationNeedsDownload,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),

            // Scrollable language list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: kTranslationLanguages.length,
                itemBuilder: (context, index) {
                  final entry = kTranslationLanguages[index];
                  final lang = entry.lang;
                  final status = _status[lang];
                  final progress = _progress[lang];
                  final isDownloading = progress != null && progress >= 0;
                  final isDeleting = progress != null && progress < 0;
                  final isWorking = isDownloading || isDeleting;
                  final isRequired = widget.requiredLanguages.contains(lang);

                  return _LanguageRow(
                    label: entry.label,
                    isDownloaded: status == true,
                    isWorking: isWorking,
                    isDownloading: isDownloading,
                    downloadProgress: isDownloading ? progress : null,
                    isRequired: isRequired,
                    colorScheme: colorScheme,
                    l10n: l10n,
                    onDownload: () => _download(lang),
                    onDelete: () => _delete(lang),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Single language row
// ---------------------------------------------------------------------------

class _LanguageRow extends StatelessWidget {
  final String label;
  final bool isDownloaded;
  final bool isWorking;
  final bool isDownloading;
  final double? downloadProgress; // 0.0–1.0 while downloading
  final bool isRequired;
  final ColorScheme colorScheme;
  final AppLocalizations l10n;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _LanguageRow({
    required this.label,
    required this.isDownloaded,
    required this.isWorking,
    required this.isDownloading,
    required this.downloadProgress,
    required this.isRequired,
    required this.colorScheme,
    required this.l10n,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final highlight = isRequired && !isDownloaded && !isWorking;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? colorScheme.primaryContainer.withValues(alpha: 0.25)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: highlight
            ? Border.all(
                color: colorScheme.primary.withValues(alpha: 0.3),
              )
            : null,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Downloaded indicator
                Icon(
                  isDownloaded
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: isDownloaded
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.25),
                ),
                const SizedBox(width: 12),

                // Name + "Required" label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (highlight) ...[
                        const SizedBox(height: 2),
                        Text(
                          l10n.languagePackRequired,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Action area
                if (isWorking)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      isDownloading
                          ? '${((downloadProgress ?? 0) * 100).round()}%'
                          : '…',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                  )
                else if (isDownloaded)
                  TextButton(
                    onPressed: onDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      l10n.languagePackDelete,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  FilledButton(
                    onPressed: onDownload,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(l10n.languagePackDownload),
                  ),
              ],
            ),
          ),

          // Progress bar during download
          if (isDownloading) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: downloadProgress,
                      minHeight: 4,
                      backgroundColor:
                          colorScheme.primary.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      l10n.languagePackDownloading,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
