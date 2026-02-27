import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';
import '../models/feed_subscription.dart';

/// Service responsible for exporting and importing feed subscriptions
/// using the OPML (Outline Processor Markup Language) format.
class OpmlService {
  /// Generates an OPML XML string from a list of [FeedSubscription]s.
  ///
  /// Feeds are grouped by their [FeedSubscription.category] as OPML outline
  /// folders, with each feed as a child `<outline>` element.
  String generateOpml(List<FeedSubscription> subscriptions) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'opml',
      attributes: {'version': '2.0'},
      nest: () {
        builder.element(
          'head',
          nest: () {
            builder.element('title', nest: 'Dondurma Rss Reader Subscriptions');
          },
        );
        builder.element(
          'body',
          nest: () {
            // Group subscriptions by category
            final Map<String, List<FeedSubscription>> grouped = {};
            for (final sub in subscriptions) {
              grouped.putIfAbsent(sub.category, () => []).add(sub);
            }

            for (final entry in grouped.entries) {
              builder.element(
                'outline',
                attributes: {'text': entry.key, 'title': entry.key},
                nest: () {
                  for (final sub in entry.value) {
                    builder.element(
                      'outline',
                      attributes: {
                        'type': 'rss',
                        'text': sub.name,
                        'title': sub.name,
                        'xmlUrl': sub.url,
                        'htmlUrl': sub.url,
                      },
                    );
                  }
                },
              );
            }
          },
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: true);
  }

  /// Parses an OPML XML [content] string and returns a list of
  /// [FeedSubscription]s.
  ///
  /// Supports both flat (no category folder) and nested (category folder)
  /// OPML structures.
  List<FeedSubscription> parseOpml(String content) {
    final List<FeedSubscription> result = [];

    late final XmlDocument document;
    try {
      document = XmlDocument.parse(content);
    } catch (_) {
      return result;
    }

    final body = document.findAllElements('body').firstOrNull;
    if (body == null) return result;

    bool foundNested = false;

    for (final topOutline in body.findElements('outline')) {
      final xmlUrl = topOutline.getAttribute('xmlUrl');

      if (xmlUrl != null && xmlUrl.isNotEmpty) {
        // This outline IS a feed (flat structure) — collect later if no nested
        continue;
      }

      // This outline is a category folder
      final category =
          topOutline.getAttribute('text') ??
          topOutline.getAttribute('title') ??
          'Uncategorized';

      final childFeeds = topOutline.findElements('outline');
      for (final feedOutline in childFeeds) {
        final feedUrl = feedOutline.getAttribute('xmlUrl');
        if (feedUrl == null || feedUrl.isEmpty) continue;

        final feedName =
            feedOutline.getAttribute('text') ??
            feedOutline.getAttribute('title') ??
            feedUrl;

        result.add(
          FeedSubscription(url: feedUrl, name: feedName, category: category),
        );
        foundNested = true;
      }
    }

    // If no nested structure was found, parse all feed outlines as flat
    if (!foundNested) {
      for (final outline in body.findAllElements('outline')) {
        final feedUrl = outline.getAttribute('xmlUrl');
        if (feedUrl == null || feedUrl.isEmpty) continue;

        final feedName =
            outline.getAttribute('text') ??
            outline.getAttribute('title') ??
            feedUrl;

        result.add(
          FeedSubscription(url: feedUrl, name: feedName, category: 'Imported'),
        );
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
          subject: 'Dondurma Rss Reader Subscriptions',
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
}
