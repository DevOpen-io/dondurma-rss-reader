import 'package:flutter/material.dart';

import '../utils/platform_caps.dart';

/// Shows [child] as a bottom sheet on mobile and a centered, width-bounded
/// dialog on desktop — the same content fills both roles.
///
/// Full-width bottom sheets look broken on a large desktop window; dialogs
/// get a comfortable reading width and bounded height instead.
///
/// The sheet draws the platform drag handle itself, so [child] never paints
/// one — a hand-drawn grabber would also show up inside the desktop dialog.
Future<T?> showAdaptiveSheet<T>(
  BuildContext context,
  Widget child, {
  double maxWidth = 560,
  bool showDragHandle = true,
}) {
  if (PlatformCaps.isDesktop) {
    return showDialog<T>(
      context: context,
      builder: (context) {
        final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
        return Dialog(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: SafeArea(child: child),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: showDragHandle,
    builder: (_) => child,
  );
}

/// A title, a body and its actions laid out for [showAdaptiveSheet]: the
/// sheet counterpart of an [AlertDialog]. The app asks and confirms in
/// bottom sheets, never in pop-up dialogs. Actions sit side by side at
/// full width, the last one being the main one; the body scrolls when the
/// sheet runs out of height and lifts above the keyboard.
class ActionSheet extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;

  const ActionSheet({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          PlatformCaps.isDesktop ? 24 : 0,
          24,
          16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              DefaultTextStyle(
                style: theme.textTheme.titleLarge!,
                child: title!,
              ),
            if (content != null) ...[
              if (title != null) const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: DefaultTextStyle(
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                    child: content!,
                  ),
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  for (final (i, action) in actions.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(height: 48, child: action),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
