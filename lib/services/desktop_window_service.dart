import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop window management: minimum size, title, and persisted bounds.
///
/// Only invoked on desktop platforms — `window_manager` has no mobile
/// implementation. Window bounds are persisted in the `settings` Hive box as
/// a small JSON map (`desktopWindowBounds`); corrupted or off-screen values
/// fall back to a centered default.
class DesktopWindowService with WindowListener {
  DesktopWindowService._();

  static const _boundsKey = 'desktopWindowBounds';
  static const Size _defaultSize = Size(1280, 800);
  static const Size _minimumSize = Size(760, 520);
  static const _appTitle = 'Dondurma RSS Reader';

  static DesktopWindowService? _instance;
  static DesktopWindowService get instance =>
      _instance ??= DesktopWindowService._();

  Timer? _saveDebounce;
  Box? _box;

  /// Initialize the window: minimum size, restored bounds, product title.
  ///
  /// Must be called after [WidgetsFlutterBinding.ensureInitialized] and
  /// `windowManager.ensureInitialized()`, before or right after `runApp`.
  Future<void> init({Box? box}) async {
    _box = box ?? (Hive.isBoxOpen('settings') ? Hive.box('settings') : null);
    windowManager.addListener(this);

    final restored = _readSavedBounds();

    const options = WindowOptions(
      minimumSize: _minimumSize,
      size: _defaultSize,
      title: _appTitle,
      titleBarStyle: TitleBarStyle.normal,
      backgroundColor: Color(0x00000000),
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      if (restored != null) {
        await windowManager.setBounds(null, size: restored.size);
        if (restored.position != null) {
          await windowManager.setPosition(restored.position!);
        }
        if (restored.maximized) {
          await windowManager.maximize();
        }
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // -------------------------------------------------------------------------
  // Persisted bounds
  // -------------------------------------------------------------------------

  ({Size size, Offset? position, bool maximized})? _readSavedBounds() {
    final raw = _box?.get(_boundsKey);
    if (raw is! String || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final w = (map['w'] as num?)?.toDouble();
      final h = (map['h'] as num?)?.toDouble();
      if (w == null || h == null) return null;
      final size = Size(
        w.clamp(_minimumSize.width, 16384),
        h.clamp(_minimumSize.height, 16384),
      );
      final x = (map['x'] as num?)?.toDouble();
      final y = (map['y'] as num?)?.toDouble();
      final position = (x != null && y != null) ? Offset(x, y) : null;
      final maximized = map['maximized'] == true;
      if (position != null && !_isOnScreen(position)) {
        // The monitor it was on is gone — drop the position so the WM
        // places it instead of leaving an unreachable window.
        return (size: size, position: null, maximized: maximized);
      }
      return (size: size, position: position, maximized: maximized);
    } catch (_) {
      return null;
    }
  }

  /// True when [position] lands inside any currently attached display.
  bool _isOnScreen(Offset position) {
    // Synchronous approximation is impossible — display queries are async —
    // so validation happens in [_persistNow]-independent form: we check at
    // restore time via the last known cursor-independent union of display
    // bounds computed in [init]. Simpler: compute eagerly here using the
    // displays queried during init.
    final displays = _displayBounds;
    if (displays == null) return true; // not queried yet — trust the value
    const margin = 48.0;
    for (final rect in displays) {
      if (position.dx >= rect.left - margin &&
          position.dx < rect.right &&
          position.dy >= rect.top - margin &&
          position.dy < rect.bottom) {
        return true;
      }
    }
    return false;
  }

  List<Rect>? _displayBounds;

  /// Snapshot the display geometry used for off-screen restore checks.
  /// Call once during init; failure leaves [_displayBounds] null (trust mode).
  Future<void> queryDisplays() async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      _displayBounds = [
        for (final d in displays)
          (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size),
      ];
    } catch (_) {
      _displayBounds = null;
    }
  }

  Future<void> _persistNow() async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    try {
      final maximized = await windowManager.isMaximized();
      final bounds = await windowManager.getBounds();
      await box.put(
        _boundsKey,
        jsonEncode({
          'w': bounds.width,
          'h': bounds.height,
          'x': maximized ? null : bounds.left,
          'y': maximized ? null : bounds.top,
          'maximized': maximized,
        }),
      );
    } catch (e) {
      debugPrint('DesktopWindowService: persist failed: $e');
    }
  }

  void _schedulePersist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_persistNow()),
    );
  }

  // -------------------------------------------------------------------------
  // WindowListener
  // -------------------------------------------------------------------------

  @override
  void onWindowResized() => _schedulePersist();

  @override
  void onWindowMoved() => _schedulePersist();

  @override
  void onWindowMaximize() => _schedulePersist();

  @override
  void onWindowUnmaximize() => _schedulePersist();

  Future<void> dispose() async {
    _saveDebounce?.cancel();
    windowManager.removeListener(this);
  }
}
