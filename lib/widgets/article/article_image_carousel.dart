import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../services/article_media_store.dart';
import '../../services/image_cache_service.dart';
import '../../utils/motion.dart';

class ArticleImageCarousel extends StatefulWidget {
  final List<String> imageUrls;

  const ArticleImageCarousel({super.key, required this.imageUrls});

  @override
  State<ArticleImageCarousel> createState() => _ArticleImageCarouselState();
}

class _ArticleImageCarouselState extends State<ArticleImageCarousel> {
  int _currentPage = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _brokenImage(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
    child: const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
  );

  @override
  Widget build(BuildContext context) {
    final imageCount = widget.imageUrls.length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Height follows the real content-column width (≈65% aspect),
          // not the whole window — the desktop reader lives inside a pane.
          final columnWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.of(context).size.width - 40;
          return Column(
            children: [
              SizedBox(
                height: columnWidth * 0.65,
            child: PageView.builder(
              controller: _pageController,
              itemCount: imageCount,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
              },
              itemBuilder: (context, index) {
                final url = widget.imageUrls[index];
                // Durable media (#41): the rewrite may point ready entries
                // at managed local files — only `m_`-scheme paths resolve.
                if (url.startsWith('file://')) {
                  final file = ArticleMediaStore.managedFileFromSrc(url);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: file == null
                        ? _brokenImage(context)
                        : Image.file(
                            file,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, _, _) => _brokenImage(context),
                          ),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    cacheManager: ArticleCacheManager.instance,
                    memCacheWidth: 800,
                    maxWidthDiskCache: 800,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorWidget: (context, url, error) => _brokenImage(context),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ...List.generate(imageCount, (index) {
                    final isActive = index == _currentPage;
                    return AnimatedContainer(
                      duration: motionDuration(
                        context,
                        const Duration(milliseconds: 250),
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isActive ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                  const SizedBox(width: 8),
                  Text(
                    '${_currentPage + 1} / $imageCount',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
