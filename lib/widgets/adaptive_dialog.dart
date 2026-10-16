import 'package:flutter/material.dart';

import '../utils/platform_caps.dart';

/// Shows [child] as a bottom sheet on mobile and a centered, width-bounded
/// dialog on desktop — the same content fills both roles.
///
/// Full-width bottom sheets look broken on a large desktop window; dialogs
/// get a comfortable reading width and bounded height instead.
Future<T?> showAdaptiveSheet<T>(
  BuildContext context,
  Widget child, {
  double maxWidth = 560,
  bool showDragHandle = false,
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
