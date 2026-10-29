import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/motion.dart';

/// Makes an article image open full screen in [ArticleImageViewer] on tap.
/// The tap wins over an enclosing link; [onOpenLink] then puts that link in
/// the viewer. While not [enabled] (a collapsed cover) the image is inert;
/// the tree keeps its shape so the image is not rebuilt.
class OpenableArticleImage extends StatelessWidget {
  final ImageProvider image;
  final Widget child;
  final bool enabled;
  final VoidCallback? onOpenLink;

  const OpenableArticleImage({
    super.key,
    required this.image,
    required this.child,
    this.enabled = true,
    this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    // A container node: inline in a paragraph, the button must not absorb
    // the surrounding text.
    return Semantics(
      container: true,
      button: enabled,
      label: enabled ? AppLocalizations.of(context).openImage : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.zoomIn : MouseCursor.defer,
        child: GestureDetector(
          behavior: enabled
              ? HitTestBehavior.opaque
              : HitTestBehavior.deferToChild,
          onTap: enabled
              ? () => ArticleImageViewer.open(
                  context,
                  image,
                  onOpenLink: onOpenLink,
                )
              : null,
          child: child,
        ),
      ),
    );
  }
}

/// A [FlexibleSpaceBar] cover that opens only while some of it shows:
/// collapsed into a pinned toolbar it is invisible and must not catch taps.
class OpenableCoverImage extends StatelessWidget {
  const OpenableCoverImage({
    super.key,
    required this.image,
    required this.child,
  });

  final ImageProvider image;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bar = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    return OpenableArticleImage(
      image: image,
      enabled: bar == null || bar.currentExtent > bar.minExtent + 1,
      child: child,
    );
  }
}

/// Full-screen, zoomable view of one article image: pinch or mouse wheel to
/// zoom, drag to pan, double tap to zoom in or reset; back, Escape or the
/// close button return to the article.
class ArticleImageViewer extends StatefulWidget {
  final ImageProvider image;

  /// Opens the link the image sits in, after the viewer closes.
  final VoidCallback? onOpenLink;

  const ArticleImageViewer({super.key, required this.image, this.onOpenLink});

  static Future<void> open(
    BuildContext context,
    ImageProvider image, {
    VoidCallback? onOpenLink,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: motionDuration(
          context,
          const Duration(milliseconds: 200),
        ),
        reverseTransitionDuration: motionDuration(
          context,
          const Duration(milliseconds: 150),
        ),
        pageBuilder: (_, _, _) =>
            ArticleImageViewer(image: image, onOpenLink: onOpenLink),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<ArticleImageViewer> createState() => _ArticleImageViewerState();
}

class _ArticleImageViewerState extends State<ArticleImageViewer> {
  static const _doubleTapScale = 2.5;

  final _transform = TransformationController();
  Offset _doubleTapAt = Offset.zero;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_transform.value.getMaxScaleOnAxis() > 1) {
      _transform.value = Matrix4.identity();
      return;
    }
    // Zoom in around the tapped point so it stays under the finger.
    const s = _doubleTapScale;
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        -_doubleTapAt.dx * (s - 1),
        -_doubleTapAt.dy * (s - 1),
        0,
        1,
      )
      ..scaleByDouble(s, s, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Decoded no larger than twice the screen: enough to zoom into, without
    // holding a camera-sized bitmap in the image cache.
    final media = MediaQuery.of(context);
    final maxPixels = (media.size.longestSide * media.devicePixelRatio * 2)
        .round();
    final onOpenLink = widget.onOpenLink;
    final viewer = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onDoubleTapDown: (details) =>
                    _doubleTapAt = details.localPosition,
                onDoubleTap: _toggleZoom,
                child: InteractiveViewer(
                  transformationController: _transform,
                  maxScale: 5,
                  child: Center(
                    child: Image(
                      image: ResizeImage(
                        widget.image,
                        width: maxPixels,
                        height: maxPixels,
                        policy: ResizeImagePolicy.fit,
                      ),
                      fit: BoxFit.scaleDown,
                      width: double.infinity,
                      height: double.infinity,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const CircularProgressIndicator(
                              color: Colors.white70,
                            ),
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 0,
                start: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      color: Colors.white,
                      tooltip: l10n.close,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ),
              if (onOpenLink != null)
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        color: Colors.white,
                        tooltip: l10n.openLink,
                        onPressed: () {
                          Navigator.of(context).pop();
                          onOpenLink();
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // Light status-bar icons over the black backdrop.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: viewer,
    );
  }
}
