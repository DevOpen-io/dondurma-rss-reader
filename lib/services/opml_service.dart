import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/feed_subscription.dart';

/// Service responsible for exporting and importing feed subscriptions
/// using the OPML (Outline Processor Markup Language) format.
class OpmlService {
  /// Generates an OPML XML string from a list of [FeedSubscription]s.
  ///
  /// Feeds are grouped by their [FeedSubscription.category] as OPML outline
  /// folders, with each feed as a child `<outline>` element.
  String generateOpml(List<FeedSubscription> subscriptions) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<opml version="2.0">');
    buffer.writeln('  <head>');
    buffer.writeln('    <title>Ice Cream Reader Subscriptions</title>');
    buffer.writeln('  </head>');
    buffer.writeln('  <body>');

    // Group subscriptions by category
    final Map<String, List<FeedSubscription>> grouped = {};
    for (final sub in subscriptions) {
      grouped.putIfAbsent(sub.category, () => []).add(sub);
    }

    for (final entry in grouped.entries) {
      final category = _escapeXml(entry.key);
      buffer.writeln('    <outline text="$category" title="$category">');
      for (final sub in entry.value) {
        final name = _escapeXml(sub.name);
        final url = _escapeXml(sub.url);
        buffer.writeln(
          '      <outline type="rss" text="$name" title="$name" xmlUrl="$url" htmlUrl="$url"/>',
        );
      }
      buffer.writeln('    </outline>');
    }

    buffer.writeln('  </body>');
    buffer.writeln('</opml>');
    return buffer.toString();
  }

  /// Parses an OPML XML [content] string and returns a list of
  /// [FeedSubscription]s.
  ///
  /// Supports both flat (no category folder) and nested (category folder)
  /// OPML structures.
  List<FeedSubscription> parseOpml(String content) {
    final List<FeedSubscription> result = [];

    // Use a simple regex-based parser to avoid adding an XML dependency.
    // Match top-level <outline> elements that act as category folders.
    final categoryRegex = RegExp(
      r'<outline\s[^>]*text="([^"]*)"[^>]*>(.*?)</outline>',
      dotAll: true,
    );
    final feedRegex = RegExp(
      r'<outline\s[^>]*xmlUrl="([^"]*)"[^>]*(?:text|title)="([^"]*)"[^>]*/?>',
      dotAll: true,
    );

    bool foundNested = false;

    for (final categoryMatch in categoryRegex.allMatches(content)) {
      final category = _unescapeXml(categoryMatch.group(1) ?? 'Uncategorized');
      final innerContent = categoryMatch.group(2) ?? '';

      // Check if this outline itself has an xmlUrl (i.e., it IS a feed, not a folder)
      if (feedRegex.hasMatch(categoryMatch.group(0)!)) {
        // It's a flat feed outline at the top level — handle below
        continue;
      }

      foundNested = true;
      for (final feedMatch in feedRegex.allMatches(innerContent)) {
        final url = _unescapeXml(feedMatch.group(1) ?? '');
        final name = _unescapeXml(feedMatch.group(2) ?? url);
        if (url.isNotEmpty) {
          result.add(
            FeedSubscription(url: url, name: name, category: category),
          );
        }
      }
    }

    // If no nested structure was found, parse all feed outlines as flat
    if (!foundNested) {
      for (final feedMatch in feedRegex.allMatches(content)) {
        final url = _unescapeXml(feedMatch.group(1) ?? '');
        final name = _unescapeXml(feedMatch.group(2) ?? url);
        if (url.isNotEmpty) {
          result.add(
            FeedSubscription(url: url, name: name, category: 'Imported'),
          );
        }
      }
    }

    return result;
  }

  /// Exports [subscriptions] as an OPML file and shares it via the system
  /// share sheet.
  ///
  /// Returns `true` on success, `false` if the share was dismissed or failed.
  Future<bool> exportOpml(List<FeedSubscription> subscriptions) async {
    try {
      final opmlContent = generateOpml(subscriptions);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ice_cream_subscriptions.opml');
      await file.writeAsString(opmlContent);

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/x-opml')],
          subject: 'Ice Cream Reader Subscriptions',
        ),
      );

      return result.status == ShareResultStatus.success ||
          result.status == ShareResultStatus.dismissed;
    } catch (_) {
      return false;
    }
  }

  /// Opens a file picker for the user to select an OPML file and returns the
  /// parsed list of [FeedSubscription]s.
  ///
  /// Returns an empty list if the user cancels or the file is invalid.
  Future<List<FeedSubscription>> importOpml() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['opml', 'xml'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return [];

      final file = result.files.first;
      String content;

      if (file.bytes != null) {
        content = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        return [];
      }

      return parseOpml(content);
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  String _unescapeXml(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }
}
