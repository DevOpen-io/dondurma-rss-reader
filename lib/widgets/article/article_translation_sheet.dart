import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/article_page_provider.dart';
import '../language_packs_sheet.dart';

/// Modal bottom sheet for selecting translation languages and triggering
/// on-device ML Kit translation for the current article.
///
/// Translation state lives in [ArticlePageProvider] — ephemeral and scoped
/// to the article's lifetime. The last used language pair is persisted to
/// the `settings` Hive box so it survives app restarts.
class ArticleTranslationSheet extends StatefulWidget {
  final ArticlePageProvider provider;

  const ArticleTranslationSheet({super.key, required this.provider});

  @override
  State<ArticleTranslationSheet> createState() =>
      _ArticleTranslationSheetState();
}

class _ArticleTranslationSheetState extends State<ArticleTranslationSheet> {
  static const _languages = kTranslationLanguages;

  TranslateLanguage _from = TranslateLanguage.english;
  TranslateLanguage _to = TranslateLanguage.turkish;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  void _loadLanguagePreference() {
    final box = Hive.box('settings');
    final fromCode = box.get('translationFromLang', defaultValue: 'en') as String;
    final toCode = box.get('translationToLang', defaultValue: 'tr') as String;
    final from = _languages.where((e) => e.lang.bcpCode == fromCode).firstOrNull;
    final to = _languages.where((e) => e.lang.bcpCode == toCode).firstOrNull;
    if (from != null || to != null) {
      setState(() {
        if (from != null) _from = from.lang;
        if (to != null) _to = to.lang;
      });
    }
  }

  Future<void> _saveLanguagePreference() async {
    final box = Hive.box('settings');
    await Future.wait([
      box.put('translationFromLang', _from.bcpCode),
      box.put('translationToLang', _to.bcpCode),
    ]);
  }

  Future<void> _doTranslate() async {
    await _saveLanguagePreference();
    await widget.provider.translate(_from, _to);
    if (!mounted) return;
    if (widget.provider.isTranslated) {
      Navigator.of(context).pop();
    } else if (widget.provider.translationNeedsDownload) {
      // Directly open language packs with required langs pre-highlighted.
      _openLanguagePacks();
    }
  }

  void _openLanguagePacks() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => LanguagePacksSheet(requiredLanguages: {_from, _to}),
    ).then((_) {
      if (mounted) widget.provider.clearTranslationNeedsDownload();
    });
  }

  void _swap() {
    setState(() {
      final tmp = _from;
      _from = _to;
      _to = tmp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        final isLoading = widget.provider.isTranslating;
        final error = widget.provider.translationError;
        final isTranslated = widget.provider.isTranslated;
        final progress = widget.provider.translationProgress;

        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.of(context).viewInsets.bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
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
              const SizedBox(height: 20),

              Text(
                l10n.translateArticle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 20),

              // Language pickers row
              Row(
                children: [
                  Expanded(
                    child: _LangColumn(
                      label: l10n.translationSourceLang,
                      value: _from,
                      languages: _languages,
                      enabled: !isLoading,
                      onChanged: (v) => setState(() => _from = v),
                      colorScheme: colorScheme,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: IconButton(
                      onPressed: isLoading ? null : _swap,
                      tooltip: l10n.translationSwapLanguages,
                      icon: Icon(
                        Icons.swap_horiz_rounded,
                        color: isLoading
                            ? colorScheme.onSurface.withValues(alpha: 0.3)
                            : colorScheme.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _LangColumn(
                      label: l10n.translationTargetLang,
                      value: _to,
                      languages: _languages,
                      enabled: !isLoading,
                      onChanged: (v) => setState(() => _to = v),
                      colorScheme: colorScheme,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Error
              if (error != null && !isLoading) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.translationError,
                          style: TextStyle(fontSize: 13, color: colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Translating spinner
              if (isLoading) ...[
                Center(
                  child: Column(
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        progress != null && progress > 0
                            ? '%${(progress * 100).round()}'
                            : l10n.translationInProgress,
                        style: TextStyle(
                          fontSize: progress != null && progress > 0 ? 15 : 13,
                          fontWeight: progress != null && progress > 0
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: progress != null && progress > 0
                              ? colorScheme.primary
                              : colorScheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action buttons
              if (!isLoading) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _from == _to ? null : _doTranslate,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      l10n.translationTranslate,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (isTranslated) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        widget.provider.clearTranslation();
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(l10n.translationClear),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widget — label + dropdown
// ---------------------------------------------------------------------------

class _LangColumn extends StatelessWidget {
  final String label;
  final TranslateLanguage value;
  final List<({TranslateLanguage lang, String label})> languages;
  final bool enabled;
  final ValueChanged<TranslateLanguage> onChanged;
  final ColorScheme colorScheme;

  const _LangColumn({
    required this.label,
    required this.value,
    required this.languages,
    required this.enabled,
    required this.onChanged,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.55),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<TranslateLanguage>(
              value: value,
              isExpanded: true,
              isDense: true,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              dropdownColor: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              onChanged: enabled ? (v) { if (v != null) onChanged(v); } : null,
              items: languages
                  .map((e) => DropdownMenuItem(value: e.lang, child: Text(e.label)))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}
