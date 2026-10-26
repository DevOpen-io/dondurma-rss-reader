import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:hive_ce/hive.dart';

import '../l10n/app_localizations.dart';
import '../services/article_record_store.dart';

/// Read-only view of quarantined legacy archive records: copies saved before
/// the per-source update whose source could not be proven. They are shown as
/// saved and never attached to a feed article (see [ArticleRecordStore]).
class LegacyArchiveScreen extends StatefulWidget {
  const LegacyArchiveScreen({super.key, this.load});

  /// Test seam; defaults to the app archive's quarantine.
  final Future<List<ArticleRecord>> Function()? load;

  @override
  State<LegacyArchiveScreen> createState() => _LegacyArchiveScreenState();
}

class _LegacyArchiveScreenState extends State<LegacyArchiveScreen> {
  late final Future<List<ArticleRecord>> _records =
      (widget.load ??
              () async => (await ArticleRecordStore.forBox(
                Hive.box('feeds'),
              ).listRecordsForGc()).quarantine)
          .call();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.legacyArchive)),
      body: FutureBuilder<List<ArticleRecord>>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final records = snapshot.data ?? const <ArticleRecord>[];
          if (records.isEmpty) {
            return Center(child: Text(l10n.legacyArchiveEmpty));
          }
          return ListView.separated(
            itemCount: records.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final record = records[index];
              return ListTile(
                title: Text(
                  _titleOf(record),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  record.siteName ?? record.feedUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _LegacyArchiveDetail(record: record),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _titleOf(ArticleRecord record) {
  final title = record.title;
  if (title != null && title.isNotEmpty) return title;
  return record.link.isNotEmpty ? record.link : record.id;
}

class _LegacyArchiveDetail extends StatelessWidget {
  const _LegacyArchiveDetail({required this.record});

  final ArticleRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.legacyArchive)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_titleOf(record), style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            l10n.legacyArchiveUnverified,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (record.body?.isNotEmpty ?? false) Html(data: record.body),
        ],
      ),
    );
  }
}
