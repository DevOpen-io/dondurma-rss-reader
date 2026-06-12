import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';

class ThumbnailCacheManager {
  ThumbnailCacheManager._();

  static final DefaultCacheManager instance = DefaultCacheManager(
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 500,
    cacheDirectoryProvider: () async {
      final dir = await getTemporaryDirectory();
      return Directory('${dir.path}/thumb_cache');
    },
  );
}

class ArticleCacheManager {
  ArticleCacheManager._();

  static final DefaultCacheManager instance = DefaultCacheManager(
    stalePeriod: const Duration(days: 3),
    maxNrOfCacheObjects: 100,
    cacheDirectoryProvider: () async {
      final dir = await getTemporaryDirectory();
      return Directory('${dir.path}/article_cache');
    },
  );
}
