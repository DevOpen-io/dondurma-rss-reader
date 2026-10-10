import 'package:flutter/widgets.dart';

/// Resolves [duration] to [Duration.zero] when the system requests reduced
/// motion (e.g. Android "Remove animations" / iOS "Reduce Motion"), leaving
/// the state change itself intact.
Duration motionDuration(BuildContext context, Duration duration) {
  return MediaQuery.maybeDisableAnimationsOf(context) == true
      ? Duration.zero
      : duration;
}
