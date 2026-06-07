import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class ArticleContentSkeleton extends StatelessWidget {
  const ArticleContentSkeleton({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Skeletonizer(
          effect: ShimmerEffect(
            baseColor: colorScheme.onSurface.withValues(alpha: 0.08),
            highlightColor: colorScheme.onSurface.withValues(alpha: 0.15),
            duration: const Duration(milliseconds: 1500),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Bone.multiText(lines: 4, fontSize: 16),
              const SizedBox(height: 20),
              Bone.multiText(lines: 3, fontSize: 16),
              const SizedBox(height: 20),
              Bone(
                height: 180,
                width: double.infinity,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(height: 20),
              Bone.multiText(lines: 5, fontSize: 16),
              const SizedBox(height: 20),
              Bone.multiText(lines: 3, fontSize: 16),
            ],
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              label!,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
