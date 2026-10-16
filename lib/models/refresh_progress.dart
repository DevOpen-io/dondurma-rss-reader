/// Observable, terminal-safe refresh status for the UI layer.
///
/// The provider exposes this via a dedicated `ValueNotifier` so progress
/// updates repaint only the toolbar — not the whole feed list.
enum RefreshPhase {
  /// No pass is running.
  idle,

  /// A refresh pass is running; counters advance as each feed settles.
  refreshing,

  /// Last pass finished; every feed fetched cleanly (200/304).
  completed,

  /// Last pass finished but at least one feed recorded a real error.
  completedWithErrors,

  /// The pass itself threw — counters are whatever they were.
  failed,

  /// The pass finished without reaching the network on any feed.
  offline,
}

/// Immutable snapshot of one refresh pass.
class RefreshProgress {
  final RefreshPhase phase;

  /// Feeds considered this pass.
  final int total;

  /// Feeds that reached a terminal outcome (success, failure, or skipped).
  final int completed;

  /// Feeds that reached the network (HTTP 200 or 304).
  final int succeeded;

  /// Feeds that recorded a failure.
  final int failed;

  /// Feeds skipped by cooldown before touching the network.
  final int skipped;

  /// Requests currently in flight.
  final int inFlight;

  /// When the pass started / when the last pass settled.
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// True when a user action (refresh button, pull-to-refresh) requested or
  /// attached to this pass. Only such passes raise the completion toast.
  final bool userInitiated;

  const RefreshProgress({
    required this.phase,
    this.total = 0,
    this.completed = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.skipped = 0,
    this.inFlight = 0,
    this.startedAt,
    this.completedAt,
    this.userInitiated = false,
  });

  const RefreshProgress.idle() : this(phase: RefreshPhase.idle);

  RefreshProgress copyWith({
    RefreshPhase? phase,
    int? total,
    int? completed,
    int? succeeded,
    int? failed,
    int? skipped,
    int? inFlight,
    DateTime? startedAt,
    DateTime? completedAt,
    bool? userInitiated,
  }) {
    return RefreshProgress(
      phase: phase ?? this.phase,
      total: total ?? this.total,
      completed: completed ?? this.completed,
      succeeded: succeeded ?? this.succeeded,
      failed: failed ?? this.failed,
      skipped: skipped ?? this.skipped,
      inFlight: inFlight ?? this.inFlight,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      userInitiated: userInitiated ?? this.userInitiated,
    );
  }
}
