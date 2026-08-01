import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AppToastType { info, success, error }

class AppToastAction {
  const AppToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

@immutable
class AppToastData {
  const AppToastData({
    required this.id,
    required this.message,
    required this.type,
    required this.duration,
    this.action,
  });

  final int id;
  final String message;
  final AppToastType type;
  final Duration duration;
  final AppToastAction? action;
}

class AppToastController extends ChangeNotifier {
  AppToastData? _current;
  Timer? _timer;
  int _nextId = 0;

  AppToastData? get current => _current;

  void show(
    String message, {
    AppToastType type = AppToastType.info,
    AppToastAction? action,
  }) {
    _timer?.cancel();
    final duration = action != null
        ? const Duration(seconds: 6)
        : type == AppToastType.error
        ? const Duration(seconds: 5)
        : const Duration(seconds: 3);
    _current = AppToastData(
      id: _nextId++,
      message: message,
      type: type,
      duration: duration,
      action: action,
    );
    notifyListeners();
    _timer = Timer(duration, dismiss);
  }

  void dismiss() {
    if (_current == null) return;
    _timer?.cancel();
    _timer = null;
    _current = null;
    notifyListeners();
  }

  void invokeAction() {
    final callback = _current?.action?.onPressed;
    if (callback == null) return;
    dismiss();
    callback();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final appToastController = AppToastController();

void showAppToast(
  String message, {
  AppToastType type = AppToastType.info,
  AppToastAction? action,
}) {
  appToastController.show(message, type: type, action: action);
}

class AppToastRouteObserver extends NavigatorObserver {
  final ValueNotifier<bool> hasModalRoute = ValueNotifier(false);
  final Set<Route<dynamic>> _modalRoutes = <Route<dynamic>>{};

  void _sync() => hasModalRoute.value = _modalRoutes.isNotEmpty;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PopupRoute) _modalRoutes.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _modalRoutes.remove(route);
    _sync();
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _modalRoutes.remove(route);
    _sync();
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _modalRoutes.remove(oldRoute);
    if (newRoute is PopupRoute) _modalRoutes.add(newRoute);
    _sync();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

final appToastRouteObserver = AppToastRouteObserver();

class AppToastHost extends StatefulWidget {
  const AppToastHost({
    super.key,
    required this.child,
    this.controller,
    this.modalListenable,
  });

  final Widget child;
  final AppToastController? controller;
  final ValueListenable<bool>? modalListenable;

  @override
  State<AppToastHost> createState() => _AppToastHostState();
}

class _AppToastHostState extends State<AppToastHost>
    with SingleTickerProviderStateMixin {
  late AppToastController _controller;
  late ValueListenable<bool> _modalListenable;
  late final AnimationController _lifetimeController;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? appToastController;
    _modalListenable =
        widget.modalListenable ?? appToastRouteObserver.hasModalRoute;
    _lifetimeController = AnimationController(vsync: this);
    _controller.addListener(_onToastChanged);
    _onToastChanged();
  }

  @override
  void didUpdateWidget(covariant AppToastHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextController = widget.controller ?? appToastController;
    if (!identical(nextController, _controller)) {
      _controller.removeListener(_onToastChanged);
      _controller = nextController;
      _controller.addListener(_onToastChanged);
      _onToastChanged();
    }
    _modalListenable =
        widget.modalListenable ?? appToastRouteObserver.hasModalRoute;
  }

  void _onToastChanged() {
    final toast = _controller.current;
    if (toast == null) {
      _lifetimeController.stop();
    } else {
      _lifetimeController.duration = toast.duration;
      _lifetimeController.forward(from: 0);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onToastChanged);
    _lifetimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _modalListenable,
      builder: (context, hasModal, _) {
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final toast = _controller.current;
        return Stack(
          children: [
            widget.child,
            if (toast != null)
              Positioned.fill(
                child: SafeArea(
                  minimum: const EdgeInsets.all(12),
                  child: AnimatedAlign(
                    key: const ValueKey('app_toast_alignment'),
                    alignment: hasModal
                        ? Alignment.topCenter
                        : Alignment.bottomCenter,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: _AppToastCard(
                      key: ValueKey(toast.id),
                      toast: toast,
                      progress: _lifetimeController,
                      reduceMotion: reduceMotion,
                      onAction: _controller.invokeAction,
                      onDismiss: _controller.dismiss,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AppToastCard extends StatelessWidget {
  const _AppToastCard({
    super.key,
    required this.toast,
    required this.progress,
    required this.reduceMotion,
    required this.onAction,
    required this.onDismiss,
  });

  final AppToastData toast;
  final Animation<double> progress;
  final bool reduceMotion;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isError = toast.type == AppToastType.error;
    final foreground = isError ? cs.onErrorContainer : cs.onInverseSurface;
    final background = isError ? cs.errorContainer : cs.inverseSurface;
    final icon = switch (toast.type) {
      AppToastType.success => Icons.check_circle_outline_rounded,
      AppToastType.error => Icons.error_outline_rounded,
      AppToastType.info => Icons.info_outline_rounded,
    };

    return Semantics(
      liveRegion: true,
      container: true,
      label: toast.message,
      onTap: onDismiss,
      child: Material(
        key: const ValueKey('app_toast'),
        color: background,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('app_toast_dismiss'),
          onTap: onDismiss,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: foreground, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      toast.message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (toast.action != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: foreground,
                        minimumSize: const Size(44, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(toast.action!.label),
                    ),
                  ],
                  const SizedBox(width: 10),
                  SizedBox.square(
                    dimension: 20,
                    child: reduceMotion
                        ? CircularProgressIndicator(
                            key: const ValueKey('app_toast_progress'),
                            value: 1,
                            strokeWidth: 2.4,
                            color: foreground,
                            backgroundColor: foreground.withValues(alpha: 0.2),
                          )
                        : AnimatedBuilder(
                            animation: progress,
                            builder: (context, _) => CircularProgressIndicator(
                              key: const ValueKey('app_toast_progress'),
                              value: 1 - progress.value,
                              strokeWidth: 2.4,
                              color: foreground,
                              backgroundColor: foreground.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
