import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/subscription_provider.dart';

/// Renders a category's icon as a user-chosen emoji when one is stored,
/// otherwise falls back to the legacy Material icon.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon({
    super.key,
    required this.category,
    required this.size,
    this.color,
  });

  final String category;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SubscriptionProvider>();
    final emoji = provider.getCategoryEmoji(category);
    if (emoji != null) {
      return Text(
        emoji,
        style: TextStyle(fontSize: size, height: 1),
        textAlign: TextAlign.center,
      );
    }
    return Icon(provider.getCategoryIcon(category), size: size, color: color);
  }
}
