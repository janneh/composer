# AGENTS.md

This file captures project-specific guidance for coding agents working on Composer. Keep it current when architecture, commands, package layout, or workflow expectations change.

## Project

Composer is a native macOS control plane for Symphony-style coding-agent orchestration. It should remain local-first, provider-neutral, and prepared for future cloud sync.

## Core Rules

- Keep interfaces generic and implementation-neutral.
- Do not make UI or orchestration code depend directly on SQLite, Linear, GitHub, Codex, Claude, Gemini, or any future provider.
- Add concrete providers behind protocols in separate packages or clearly isolated targets.
- Prefer small vertical slices that compile and preserve the provider boundaries.
- Update `PLAN.md` when roadmap, sequencing, or architectural intent changes.
- Update this file when build commands, package layout, or contributor guidance changes.

## Current Package Layout

- `SymphonyCore`: provider-neutral domain models and identifiers.
- `SymphonyInterfaces`: ports/protocols for stores, trackers, workflow, workspace, agents, sync, and runtime events.
- `SymphonyLocalStore`: local JSON store for initial development and tests.
- `SymphonyRuntime`: orchestration state-machine skeleton.
- `ComposerApp`: SwiftUI macOS UI.
- `ComposerCLI`: `composerctl` command-line surface for inserting projects/tasks into the same local store as the app.
- `Tests/SymphonyCoreTests`: focused domain tests.

## Planned Packages

- `SymphonySQLiteStore`: durable local storage with migrations and event log.
- `SymphonyWorkflow`: `WORKFLOW.md` discovery, validation, and prompt rendering.
- `SymphonyWorkspace`: workspace/worktree lifecycle.
- `SymphonyCodexAgent`: Codex runner.
- `SymphonyClaudeAgent`: Claude runner.
- `SymphonyGeminiAgent`: Gemini runner.

## Build And Test

Use workspace-local caches because sandboxed agent sessions may not be able to write SwiftPM or Clang caches under the user home directory.

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
  swift test --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache"
```

Run the app with:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
  swift run --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache" Composer
```

Run the CLI with:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
  swift run --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache" composerctl help
```

## Implementation Notes

- `WorkItem`, `Project`, `RunAttempt`, and runtime events live in `SymphonyCore`.
- Storage mutations currently go through `LocalJSONStore`, but call sites should use protocol-shaped APIs where practical.
- CLI mutations must append runtime events just like UI mutations.
- User-visible edits should append runtime events where useful so later sync has a clear mutation history.
- Keep SwiftUI views focused on presentation; move provider/runtime behavior into packages as it grows.
