import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/article_identity.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/utils/feed_text.dart';

void main() {
  group('sanitizeSiteTitle drops a tagline', () {
    test('after a pipe, with or without spaces', () {
      expect(
        ArticleIdentity.sanitizeSiteTitle(
          'Apartment Therapy| Saving the world, one room at a time',
        ),
        'Apartment Therapy',
      );
      expect(
        ArticleIdentity.sanitizeSiteTitle(
          'Kottke | Home of fine hypertext products since 1998',
        ),
        'Kottke',
      );
    });

    test('after a spaced dash of any width', () {
      expect(
        ArticleIdentity.sanitizeSiteTitle(
          'TechCrunch – Startup and Technology News',
        ),
        'TechCrunch',
      );
      expect(
        ArticleIdentity.sanitizeSiteTitle(
          'Example Blog — Notes on design, code and everything else',
        ),
        'Example Blog',
      );
      expect(
        ArticleIdentity.sanitizeSiteTitle(
          'Daring Fireball - By John Gruber about the things he likes',
        ),
        'Daring Fireball',
      );
    });

    test('keeps section feeds and names that contain a dash', () {
      for (final title in [
        'The Verge - All Posts',
        'BBC News - World',
        'The Guardian | Technology',
        'Ars Technica - All content',
        'Spider-Man News',
        'Self-Hosted Weekly',
        'A Name-With-Dashes - Blog',
        'NYT > Top Stories',
        '500px ISO',
      ]) {
        expect(ArticleIdentity.sanitizeSiteTitle(title), title, reason: title);
      }
    });

    test('keeps a title whose first part is not a plausible name', () {
      // A long first part is a sentence, not a site name.
      const title =
          'Why we stopped shipping on Fridays and what changed for the team '
          '- a retrospective of the first six months';
      expect(ArticleIdentity.sanitizeSiteTitle(title), title);
      // Empty name part.
      expect(
        ArticleIdentity.sanitizeSiteTitle('| Saving the world, one room'),
        '| Saving the world, one room',
      );
    });

    test('cached items are cleaned on load too', () {
      final item = FeedItem.fromJson({
        'id': '1',
        'siteName': 'Apartment Therapy| Saving the world, one room at a time',
        'title': 't',
        'feedUrl': 'https://www.apartmenttherapy.com/main.rss',
      });
      expect(item.siteName, 'Apartment Therapy');
    });
  });

  group('cleanExcerpt strips trailing read-more boilerplate', () {
    test('READ MORE... and its variants', () {
      expect(
        cleanExcerpt('A small kitchen gets a bold blue makeover. READ MORE...'),
        'A small kitchen gets a bold blue makeover.',
      );
      expect(
        cleanExcerpt('A small kitchen gets a bold blue makeover READ MORE…'),
        'A small kitchen gets a bold blue makeover',
      );
      expect(
        cleanExcerpt('The team shipped the release. Read more'),
        'The team shipped the release.',
      );
      expect(
        cleanExcerpt('The team shipped the release. Read more »'),
        'The team shipped the release.',
      );
      expect(
        cleanExcerpt('The team shipped the release. [Read more]'),
        'The team shipped the release.',
      );
    });

    test('Continue reading with the post title', () {
      expect(
        cleanExcerpt(
          'It was a long winter. Continue reading “Notes from the cabin” →',
        ),
        'It was a long winter.',
      );
      expect(
        cleanExcerpt('It was a long winter … Continue reading'),
        'It was a long winter …',
      );
    });

    test('WordPress […] and "The post … appeared first on …"', () {
      expect(
        cleanExcerpt('The first paragraph of the story [&#8230;]'),
        'The first paragraph of the story …',
      );
      expect(
        cleanExcerpt('The first paragraph of the story […]'),
        'The first paragraph of the story …',
      );
      expect(
        cleanExcerpt(
          'The first paragraph of the story [...] The post How we '
          'renovated a tiny flat appeared first on Example Blog.',
        ),
        'The first paragraph of the story …',
      );
    });

    test('leaves ordinary text alone', () {
      for (final text in [
        'You can read more about it in our guide.',
        'Scientists want to read more of the scrolls',
        'He kept reading until dawn.',
        'Prices rose 3% - the most since 2019.',
        'The post office reopened on Monday.',
        'Wait for it...',
        '',
      ]) {
        expect(cleanExcerpt(text), text, reason: text);
      }
    });

    test('is applied to parsed descriptions and cached items', () async {
      const rss = '''<?xml version="1.0"?>
<rss version="2.0"><channel>
<title>Apartment Therapy| Saving the world, one room at a time</title>
<link>https://www.apartmenttherapy.com</link>
<item><title>Blue kitchen</title><link>https://example.com/a</link>
<guid>a</guid>
<description>&lt;p&gt;A small kitchen gets a bold blue makeover.&lt;/p&gt; &lt;a href="https://example.com/a"&gt;READ MORE...&lt;/a&gt;</description>
</item></channel></rss>''';
      final items = FeedService.parseFeedBody((
        bodyBytes: utf8.encode(rss),
        category: 'c',
        url: 'https://www.apartmenttherapy.com/main.rss',
        contentType: 'application/rss+xml',
      ));
      expect(items.single.siteName, 'Apartment Therapy');
      expect(
        items.single.description,
        'A small kitchen gets a bold blue makeover.',
      );

      final cached = FeedItem.fromJson({
        'id': '1',
        'title': 't',
        'description': 'Old cached excerpt. READ MORE...',
      });
      expect(cached.description, 'Old cached excerpt.');
    });
  });
}
