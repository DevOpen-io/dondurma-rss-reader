import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp('category-emoji-');
    Hive.init(tempDirectory.path);
    await Hive.openBox('feeds');
  });

  setUp(() async {
    await Hive.box('feeds').clear();
  });

  test('setCategoryEmoji stores and returns the emoji', () async {
    final provider = SubscriptionProvider();
    await provider.setCategoryEmoji('News', '🚀');
    expect(provider.getCategoryEmoji('News'), '🚀');
  });

  test('multi-grapheme input keeps only the first grapheme cluster', () async {
    final provider = SubscriptionProvider();
    await provider.setCategoryEmoji('Fun', '😀🎉abc');
    expect(provider.getCategoryEmoji('Fun'), '😀');
  });

  test('ZWJ emoji is kept as a single grapheme cluster', () async {
    final provider = SubscriptionProvider();
    const family = '👨‍👩‍👧';
    await provider.setCategoryEmoji('Fam', family);
    expect(provider.getCategoryEmoji('Fam'), family);
  });

  test('getCategoryIcon never clobbers a stored emoji', () async {
    final provider = SubscriptionProvider();
    await provider.setCategoryEmoji('News', '🚀');
    // Reading the Material fallback must not rewrite the stored emoji.
    provider.getCategoryIcon('News');
    expect(provider.getCategoryEmoji('News'), '🚀');
  });

  test('empty input restores the default icon', () async {
    final provider = SubscriptionProvider();
    await provider.setCategoryEmoji('News', '🚀');
    await provider.setCategoryEmoji('News', '   ');
    expect(provider.getCategoryEmoji('News'), isNull);
  });

  test('legacy numeric codePoint values still resolve to Material icons', () {
    final provider = SubscriptionProvider();
    expect(provider.getCategoryEmoji('News'), isNull);
    expect(provider.getCategoryIcon('News'), isNotNull);
  });
}
