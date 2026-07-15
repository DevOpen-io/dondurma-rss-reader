# Critique — lib/widgets/feed_list_item.dart

- Date: 2026-07-15
- Target: lib/widgets/feed_list_item.dart (home feed card)
- Register: product
- Detector: ran, no signal (Dart source, out of detector domain)

## Findings

- **[P1] Missing category name** — card shows category icon (40×40 tile) but no label; 30+ similar folder/tag glyphs are not self-explanatory. Add `siteName · categoryName` meta row, plain onSurfaceVariant text, no colored chip (zero-noise).
- **[P1] Contrast (repeat of 2026-07-04 P2)** — date 11px @ onSurface α0.55 ≈ 3.4–3.7:1 FAIL; read-state description α0.55 FAIL; read site name α0.6 borderline. Fix: onSurfaceVariant token.
- **[P1] Touch targets** — `_ActionIcon` 40×40, thumbnail bookmark chip 44×44; Material min 48×48.
- **[P1] Swipe a11y** — bookmark/read-toggle swipe actions invisible to TalkBack; no CustomSemanticsAction. Read-toggle has NO non-swipe affordance at all.
- **[P2] Hierarchy inversion** — site name in colorScheme.primary + w600 on top row competes with title. Demote to onSurfaceVariant; unread signal = dot + title weight.
- **[P2] Theme-alien icon colors** — item.iconColor/iconBackgroundColor hardcoded 0xFF00A3FF in feed_service; clashes with all 10 FlexColorScheme themes. Fix in-card: primaryContainer/onPrimaryContainer.
- **[P2] Hardcoded shadow** — Colors.black α0.06 blur 12: invisible in dark mode, non-M3 in light. Replace with surfaceContainerLow surface.
- **[P3] Unread bg tint (7% primary)** — third redundant unread channel, too subtle to read, can produce muddy surfaces on saturated themes. Remove.

## Decisions

- Reading time on card: **rejected** — most feeds excerpt-only → misleading estimate; per-item word count during list scroll costs. Revisit only if user asks.
- Radius 18 (M3 says 12): left alone, surgical scope.

## Planned fixes (Phase 2, pending approval)

1. Meta row `siteName · category` (plain text)
2. Site name primary → onSurfaceVariant
3. Remove unread bg tint
4. Icon tile → primaryContainer/onPrimaryContainer
5. Shadow → surfaceContainerLow
6. α0.55/0.6 → onSurfaceVariant
7. 48×48 touch targets
8. CustomSemanticsAction for bookmark + read toggle
