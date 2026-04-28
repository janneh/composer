# AGENTS.md

This file captures project-specific guidance for coding agents working on Composer. Keep it current when architecture, commands, package layout, or workflow expectations change.

## Project

Composer is a native macOS control plane for Symphony-style coding-agent orchestration. It should remain local-first, provider-neutral, and prepared for future cloud sync.

The repository is licensed under Apache-2.0.

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

Use `make` for normal development commands. The Makefile keeps SwiftPM and Clang caches inside `.build` because sandboxed agent sessions may not be able to write caches under the user home directory.

Common commands:

```sh
make test
make build
make app
make cli
make smoke-cli
```

`make cli` installs `composerctl` to `~/.local/bin`. After that, use the CLI directly:

```sh
composerctl help
composerctl task list
```

Raw SwiftPM commands are acceptable when diagnosing Makefile behavior, but keep the Makefile as the documented entry point.

Underlying pattern, if needed:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
  swift test --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache"
```

## Implementation Notes

- `WorkItem`, `Project`, `RunAttempt`, and runtime events live in `SymphonyCore`.
- Storage mutations currently go through `LocalJSONStore`, but call sites should use protocol-shaped APIs where practical.
- CLI mutations must append runtime events just like UI mutations.
- `ComposerApp` consumes an `AsyncThrowingStream` of local store file changes so `composerctl` updates are reflected without restarting the app.
- User-visible edits should append runtime events where useful so later sync has a clear mutation history.
- Keep SwiftUI views focused on presentation; move provider/runtime behavior into packages as it grows.
