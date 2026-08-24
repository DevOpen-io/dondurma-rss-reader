# Global Toast Overlay

Date: 2026-08-01
Status: implemented. Current source: `lib/utils/app_toast.dart`; tests: `test/app_toast_test.dart`. Historical design record; code wins on drift.

## Goal

Replace app snackbars with one global toast system that always appears above routes, dialogs, and bottom sheets. Every toast dismisses automatically and shows its remaining lifetime with a circular progress indicator.

## Behavior

- Only one toast may be visible. A new toast immediately replaces the current toast; messages never queue.
- Success messages remain visible for 3 seconds.
- Error messages remain visible for 5 seconds.
- Messages containing an Undo action remain visible for 6 seconds.
- The progress ring at the trailing edge drains clockwise over the toast lifetime. The toast dismisses when the ring completes.
- Invoking an action dismisses the toast before running its callback.
- Tapping anywhere on the toast body dismisses it immediately. Tapping the optional action runs only that action and does not also trigger the body dismissal handler.
- Normal routes place the toast at bottom-center, above the safe area and bottom navigation.
- Open dialogs or bottom sheets place the toast at top-center, below the safe area.
- Route changes and modal transitions must not hide or dispose the toast early.

## Visual Design

The toast uses the existing Material 3 color scheme and Outfit typography.

Content order:

1. Semantic status icon
2. Flexible, wrapping message
3. Optional text action such as Undo
4. Circular lifetime indicator

Success and informational messages use the normal elevated surface treatment. Errors use `errorContainer` and `onErrorContainer`. Shape radius remains within the established component vocabulary. The toast respects compact phone widths, large text scaling, light mode, dark mode, and high-contrast mode.

## Architecture

### Global host

Install an `AppToastHost` above the router content through `MaterialApp.router.builder`. The host owns the visual overlay and therefore renders above navigator routes, dialogs, and modal bottom sheets.

### Controller

Expose an application-level `AppToastController` with a single active toast value. Callers publish an `AppToastData` value containing:

- message
- semantic type (`info`, `success`, or `error`)
- optional action label and callback
- duration derived from type and action presence

Publishing replaces the previous value and resets the timer. Dismissal clears the active value.

### Modal awareness

The host observes route stack changes through a navigator observer. Dialog and bottom-sheet routes mark modal presence. Any active toast animates between bottom-center and top-center when modal state changes.

### Compatibility helper

Replace `showAppSnackBar` with a toast helper so existing call sites migrate with minimal churn. New APIs must describe toast intent instead of accepting `ScaffoldMessengerState`.

All direct `ScaffoldMessenger` and `SnackBar` usages in `lib/` move to the global helper.

## RSS Feed Errors

Field-specific validation remains inline beneath the URL field. Network, parsing, and subscription-operation failures also produce a global error toast, ensuring feedback remains visible while the add-feed bottom sheet is open.

Successful feed addition closes the sheet and shows a success toast. Suggested-feed subscribe and unsubscribe actions use the same host and retain Undo support.

## Motion and Accessibility

- Toast entrance, exit, and position changes use 150–250 ms ease-out motion.
- The lifetime indicator represents actual remaining duration.
- When reduced motion is enabled, entrance and position animations become immediate or crossfade-only. The ring remains static; timed dismissal still occurs.
- Toast content uses a live-region semantic announcement.
- Action labels remain independently tappable and accessible.
- The toast body exposes an accessible dismiss action.
- Text wraps without colliding with the action or progress ring at large text scale.

## Error Handling

- Calling dismiss when no toast exists is a no-op.
- Replacing a toast cancels its timer and animation controller.
- Action callbacks run once, after dismissal.
- Host disposal cancels timers and listeners.
- Toast presentation does not depend on a call-site `BuildContext` surviving an async gap.

## Testing

Widget tests cover:

- success dismissal after 3 seconds
- error dismissal after 5 seconds
- Undo dismissal after 6 seconds
- progress ring lifetime
- replacing the active toast without queueing
- action invocation exactly once
- body-tap dismissal without invoking the optional action
- bottom placement on normal routes
- top placement above a modal bottom sheet
- reduced-motion behavior
- long text and increased text scaling

Static checks confirm no direct `SnackBar` or `ScaffoldMessenger.showSnackBar` usages remain in `lib/`.

## Success Criteria

- No toast remains stuck indefinitely.
- Every toast visibly communicates when it will close.
- No dialog, bottom sheet, or route obscures a toast.
- Existing success, error, and Undo flows retain their behavior.
- RSS add errors are visible while the form remains open.
- Analyzer and relevant widget tests pass.
