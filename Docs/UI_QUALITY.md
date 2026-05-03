# Composer UI Quality Guide

This guide defines the guardrails for keeping Composer's macOS UI consistent as it grows. It is intentionally practical: every UI change should either follow these rules or update them with a clear reason.

## Design Tokens

- Put shared colors, typography, radii, and spacing in `Sources/ComposerApp/ComposerTheme.swift`.
- Use `ComposerTheme` for semantic colors and fonts. Avoid ad hoc hex colors inside feature views.
- Use `ComposerLayout` for structural dimensions: sidebar widths, inspector width, board column width, workspace padding, and compact breakpoints.
- Add a token when a value appears in multiple places or defines product rhythm. Keep one-off values local only when they are truly component-specific.

## UI Primitives

- Prefer the primitives in `Sources/ComposerApp/ComposerPrimitives.swift` for repeated UI shapes such as header actions, metadata chips, priority badges, label rows, and flow layout.
- If a view repeats a layout pattern three times, extract it before adding the fourth use.
- Keep primitives provider-neutral. They should not know about Codex, GitHub, Linear, SQLite, or workflow implementation details.

## Layout Rules

- `RootView` owns the high-level split only. Feature surfaces live in focused files such as `SidebarView`, `ProjectWorkspaceView`, `BoardView`, and `InspectorView`.
- The sidebar uses a stable width range and owns its own vertical scroll behavior.
- Project header controls stay docked at the top of the workspace and span the available content width.
- Diagnostics sit below the project header. The board starts immediately below diagnostics and grows downward.
- The board owns horizontal scrolling. The selected-task inspector owns vertical scrolling.
- Avoid nested scroll views unless each scroll axis is explicit and tested in a small window.
- Use clear borders or shared backgrounds between adjacent UI regions. Avoid partial color transitions that look clipped.

## State Coverage

Visual checks should cover these states before a UI change is considered finished:

- Empty project with no repository configured.
- Workflow diagnostic banner visible.
- Tasks present in each board lane: backlog, ready, running, human review, merging, and done.
- Selected task inspector with long title, description, labels, blocked-by references, and runtime events.
- No selected task.
- Compact window width below `ComposerLayout.compactWorkspaceWidth`.
- Light and dark appearance when color or material tokens change.

## Screenshot Checks

Use the screenshot harness for repeatable visual checks:

```sh
make ui-screenshots
make ui-check
```

`make ui-screenshots` builds the app, creates a deterministic local JSON store, launches Composer against that store, and writes captures to `Artifacts/UI`.

`make ui-check` captures the same screens and compares them against `References/UI` when baselines exist. To bless an intentional change:

```sh
Scripts/capture-ui-screenshots.sh bless
```

The harness uses macOS accessibility and screen capture APIs, so the first local run may need system permission. Close any running Composer instance before using it so the fixture store is the only active app state.

## Review Checklist

- Tokens: new colors, fonts, radii, and repeated spacing are in `ComposerTheme` or `ComposerLayout`.
- Structure: root scenes and feature views stay small enough to scan.
- States: empty, populated, selected, compact, disabled, error, and loading states have been exercised.
- Scroll: every narrow or short-window layout can reach the bottom of the active content.
- Motion: mutations do not cause full-view blinking or unnecessary replacement of large view trees.
- Accessibility: interactive controls have labels or help text, and icon-only controls explain their purpose.
- Boundaries: UI code depends on provider-neutral models and protocols, not concrete storage, tracker, or agent implementations.
