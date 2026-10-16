import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/refresh_progress.dart';
import '../providers/feed_provider.dart';
import '../utils/app_toast.dart';

/// Emits a single [showAppToast] summary when a user-initiated refresh pass
/// reaches a terminal phase.
///
/// Plain class so provider-level tests can drive it without a widget tree;
/// [RefreshCompletionListener] wires it to the live progress notifier.
class RefreshToastAnnouncer {
  /// Dedupes toasts: a pass settles exactly once, but several notifier
  /// emissions can share the same [RefreshProgress.completedAt].
  DateTime? _lastToastedAt;

  void onProgress(RefreshProgress progress, AppLocalizations l10n) {
    if (!progress.userInitiated) return;
    if (!_isTerminal(progress.phase)) return;
    final stamp = progress.completedAt;
    if (stamp == null || stamp == _lastToastedAt) return;
    _lastToastedAt = stamp;

    switch (progress.phase) {
      case RefreshPhase.completed:
        if (progress.total == 0) {
          showAppToast(l10n.refreshToastEmpty);
        } else {
          showAppToast(
            l10n.refreshToastSuccess(progress.succeeded),
            type: AppToastType.success,
          );
        }
      case RefreshPhase.completedWithErrors:
        showAppToast(
          l10n.refreshToastPartial(
            progress.succeeded,
            progress.failed,
            progress.skipped,
          ),
        );
      case RefreshPhase.offline:
        showAppToast(l10n.offlineBanner);
      case RefreshPhase.failed:
        showAppToast(
          l10n.refreshToastFailed(progress.total),
          type: AppToastType.error,
        );
      case RefreshPhase.idle || RefreshPhase.refreshing:
        break;
    }
  }

  bool _isTerminal(RefreshPhase phase) =>
      phase == RefreshPhase.completed ||
      phase == RefreshPhase.completedWithErrors ||
      phase == RefreshPhase.failed ||
      phase == RefreshPhase.offline;
}

/// Listens to [FeedProvider.refreshProgress] above both home shells so mobile
/// and desktop share the same completion-toast behavior.
class RefreshCompletionListener extends StatefulWidget {
  const RefreshCompletionListener({super.key, required this.child});

  final Widget child;

  @override
  State<RefreshCompletionListener> createState() =>
      _RefreshCompletionListenerState();
}

class _RefreshCompletionListenerState extends State<RefreshCompletionListener> {
  final _announcer = RefreshToastAnnouncer();
  FeedProvider? _provider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<FeedProvider>();
    if (!identical(provider, _provider)) {
      _provider?.refreshProgress.removeListener(_onProgress);
      _provider = provider;
      provider.refreshProgress.addListener(_onProgress);
    }
  }

  @override
  void dispose() {
    _provider?.refreshProgress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (!mounted) return;
    _announcer.onProgress(
      _provider!.refreshProgress.value,
      AppLocalizations.of(context),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
