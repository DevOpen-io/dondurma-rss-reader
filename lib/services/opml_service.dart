import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';
import '../models/feed_subscription.dart';
import '../utils/platform_caps.dart';

/// Service responsible for exporting and importing feed subscriptions
/// using the OPML (Outline Processor Markup Language) format.
///
/// OPML is the standard interchange format for RSS feed lists. This service
/// supports both nested (category folders) and flat OPML structures.
class OpmlService {
  /// Generates an OPML 2.0 XML string from a list of [FeedSubscription]s.
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
  /// OPML structures. Returns an empty list if parsing fails.
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

    // Both passes run unconditionally: real exports mix folders and
    // loose top-level feeds — a `foundNested` gate would silently drop
    // every root-level feed whenever any folder contains one (#53).
    for (final topOutline in body.findElements('outline')) {
      final xmlUrl = topOutline.getAttribute('xmlUrl');

      if (xmlUrl != null && xmlUrl.isNotEmpty) {
        // This outline IS a feed (flat / loose top-level entry).
        final feedName =
            topOutline.getAttribute('text') ??
            topOutline.getAttribute('title') ??
            xmlUrl;
        result.add(
          FeedSubscription(url: xmlUrl, name: feedName, category: 'Imported'),
        );
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
      }
    }

    return result;
  }

  /// Exports [subscriptions] as an OPML file.
  ///
  /// Mobile shares via the system sheet; desktop uses the native save dialog
  /// so the user picks the destination. Returns `true` on success or user
  /// cancellation, `false` if an error occurred.
  Future<bool> exportOpml(List<FeedSubscription> subscriptions) async {
    try {
      final opmlContent = generateOpml(subscriptions);

      if (!PlatformCaps.supportsShareSheet) {
        const typeGroup = XTypeGroup(label: 'OPML', extensions: ['opml']);
        final location = await getSaveLocation(
          acceptedTypeGroups: [typeGroup],
          suggestedName: 'dondurma_subscriptions.opml',
        );
        if (location == null) return true; // cancelled — not an error
        var path = location.path;
        if (!path.toLowerCase().endsWith('.opml')) path = '$path.opml';
        await File(path).writeAsString(opmlContent, flush: true);
        return true;
      }

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
      const typeGroup = XTypeGroup(label: 'OPML', extensions: ['opml', 'xml']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return [];

      // Not `readAsString`: for the bytes the Android picker returns it
      // decodes Latin-1 whatever encoding it is given.
      final content = utf8.decode(await file.readAsBytes());
      return parseOpml(content);
    } catch (_) {
      return [];
    }
  }
}
