import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class FeedListSkeleton extends StatelessWidget {
  const FeedListSkeleton({super.key, this.itemCount = 6, this.showHeader = true});

  final int itemCount;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      effect: ShimmerEffect(
        baseColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.08),
        highlightColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.15),
        duration: const Duration(milliseconds: 1500),
      ),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: itemCount + (showHeader ? 1 : 0),
        itemBuilder: (context, index) {
          if (showHeader && index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Bone.text(words: 1, fontSize: 12),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.square(
                    size: 44,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Bone.text(words: 2, fontSize: 12)),
                            const SizedBox(width: 8),
                            Bone.text(words: 1, fontSize: 11),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Bone.multiText(lines: 2, fontSize: 15),
                        const SizedBox(height: 4),
                        Bone.text(words: 5, fontSize: 13),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Bone.icon(size: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
