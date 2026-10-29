import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/motion.dart';

/// Makes an article image open full screen in [ArticleImageViewer] on tap.
/// The tap wins over an enclosing link: the viewer has its own way out.
class OpenableArticleImage extends StatelessWidget {
  final ImageProvider image;
  final Widget child;

  const OpenableArticleImage({
    super.key,
    required this.image,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).openImage,
      child: MouseRegion(
        cursor: SystemMouseCursors.zoomIn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ArticleImageViewer.open(context, image),
          child: child,
        ),
      ),
    );
  }
}

/// Full-screen, zoomable view of one article image: pinch or mouse wheel to
/// zoom, drag to pan, double tap to zoom in or reset; back, Escape or the
/// close button return to the article.
class ArticleImageViewer extends StatefulWidget {
  final ImageProvider image;

  const ArticleImageViewer({super.key, required this.image});

  static Future<void> open(BuildContext context, ImageProvider image) {
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
        pageBuilder: (_, _, _) => ArticleImageViewer(image: image),
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
    return CallbackShortcuts(
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
                      image: widget.image,
                      fit: BoxFit.contain,
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
            ],
          ),
        ),
      ),
    );
  }
}
