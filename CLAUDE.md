# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read [AGENTS.md](AGENTS.md) for shared project constraints and task-specific documentation. [docs/README.md](docs/README.md) indexes current guides and historical records.

## Communication Style

Use caveman skill. Terse responses. Drop filler, articles, hedging. Fragments OK. Technical terms exact. Code unchanged.

**Prefer MCP over raw terminal** for tooling — especially **Dart/Flutter**: use the configured Dart MCP server (analysis, fixes, project queries) before defaulting to CLI-only workflows when the MCP tool covers the task.

**Prefer TDD when practical:** write or adjust failing tests first for new behavior or bug fixes, then implement until green; skip only where a test would not add signal (e.g. pure UI snapshot churn) — default bias is test-first.

- Use available repository skills when their trigger matches.
- Avoid mutating Git history or user changes. Read-only Git inspection is allowed.
- **UI/UX Excellence:** Exhibit impeccable skill in frontend design. Deliver modern, polished, and pixel-perfect layouts with exceptional attention to spacing, typography, and visual hierarchy.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

## Technical reference

Shared architecture and persistence rules live in [the architecture guide](docs/development/architecture.md). Read [offline storage](docs/development/offline-storage.md) for ownership, preparation and cleanup changes; read [the release guide](docs/operations/releases.md) before build/signing/submission work.

