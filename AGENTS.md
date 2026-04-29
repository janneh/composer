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
- `SymphonySQLiteStore`: durable SQLite store conforming to the same store protocols. It currently preserves full domain objects as JSON payloads plus indexed columns for queries.
- `ComposerStorage`: edge-level storage factory for choosing JSON or SQLite while returning protocol-shaped stores.
- `SymphonyWorkflow`: `WORKFLOW.md` discovery/loading, Markdown front matter parsing, UI diagnostics, and prompt rendering.
- `SymphonyWorkspace`: local workspace provider that prepares per-task Git worktrees behind the generic workspace protocol.
- `SymphonyRuntime`: orchestration state-machine skeleton.
- `ComposerApp`: SwiftUI macOS UI.
- `ComposerCLI`: `composerctl` command-line surface for inserting projects/tasks into the same local store as the app.
- `Tests/SymphonyCoreTests`: focused domain tests.
- `Tests/ComposerAppTests`: app storage configuration and composition tests.

The repository also contains `Composer.xcodeproj`, which builds and launches the macOS `.app` bundle. Keep SwiftPM as the package/module boundary, and keep the Xcode project in sync when app-facing source files or app-linked framework targets change.

Xcode framework targets used by the app must keep `LD_DYLIB_INSTALL_NAME` set to `@rpath/$(EXECUTABLE_PATH)` so the app loads embedded Composer frameworks from `Composer.app/Contents/Frameworks` instead of `/Library/Frameworks`.

## Planned Packages

- `SymphonyCodexAgent`: Codex runner.
- `SymphonyClaudeAgent`: Claude runner.
- `SymphonyGeminiAgent`: Gemini runner.

## Build And Test

Use `make` for normal development commands. The Makefile keeps SwiftPM and Clang caches inside `.build` because sandboxed agent sessions may not be able to write caches under the user home directory.

Common commands:

```sh
make test
make build
make xcode-build
make app
make open-project
make cli
make smoke-cli
make smoke-cli-sqlite
```

`make app` builds the checked-in Xcode project and opens the resulting `Composer.app`. Use `make open-project` when working directly in Xcode.

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
- Storage mutations should go through protocol-shaped APIs where practical. Concrete backend selection belongs at app/CLI edges.
- `composerctl` defaults to JSON storage and can use SQLite with `--store-backend sqlite`; `ComposerApp` uses `ComposerStorage` and can select JSON or SQLite with `COMPOSER_STORE_BACKEND`, `COMPOSER_STORE_PATH`, or the `ComposerStoreBackend` / `ComposerStorePath` app defaults.
- CLI mutations must append runtime events just like UI mutations.
- `ComposerApp` consumes an `AsyncThrowingStream` of JSON store file changes so `composerctl` JSON updates are reflected without restarting the app. SQLite app refresh is currently explicit/in-process.
- `SymphonyWorkflow.WorkflowLoader` resolves explicit workflow paths first, otherwise uses `WORKFLOW.md` under the project repository path.
- Workflow front matter supports a conservative `key: value` subset with strings, booleans, integers, doubles, and inline string lists.
- `ComposerApp` publishes selected-project workflow diagnostics from `WorkflowLoader` and shows them above the board.
- `SymphonyWorkflow.FileWorkflowProvider` adapts loaded workflow documents to the generic `WorkflowProvider` prompt interface.
- `SymphonyWorkspace.LocalWorkspaceProvider` prepares deterministic per-task workspaces as detached Git worktrees under a configurable root directory.
- User-visible edits should append runtime events where useful so later sync has a clear mutation history.
- Keep SwiftUI views focused on presentation; move provider/runtime behavior into packages as it grows.
