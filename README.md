# Composer

Composer is a native macOS control surface for Symphony-style agent orchestration.

It is inspired by OpenAI's [Symphony orchestration spec](https://github.com/openai/symphony/blob/main/SPEC.md).

Licensed under the [Apache License 2.0](LICENSE).

The first implementation keeps the important boundaries generic:

- `SymphonyCore`: provider-neutral domain models for projects, work items, runs, agents, and runtime events.
- `SymphonyInterfaces`: protocol boundaries for storage, trackers, workflow loading, workspaces, agent runners, sync, and event sinks.
- `SymphonyLocalStore`: a local JSON-backed store selectable by the app and CLI.
- `SymphonySQLiteStore`: a durable SQLite-backed store with versioned schema setup, indexed queries, and JSON payload preservation.
- `SymphonyWorkflow`: `WORKFLOW.md` discovery, loading, Markdown front matter parsing, UI diagnostics, and prompt rendering.
- `SymphonyWorkspace`: local per-task workspace preparation backed by Git worktrees, with cleanup policy metadata on runs.
- `SymphonyCodexAgent`: Codex CLI runner implementation behind the generic `AgentRunner` protocol.
- `SymphonyClaudeAgent`: Claude Code CLI runner implementation behind the generic `AgentRunner` protocol.
- `SymphonyGeminiAgent`: Gemini CLI runner implementation behind the generic `AgentRunner` protocol.
- `SymphonyLinearTracker`: Linear GraphQL adapter behind the generic `TrackerClient` protocol.
- `ComposerStorage`: app/CLI storage composition and backend selection.
- `SymphonyRuntime`: dispatch planning/execution, run control, runtime service/XPC boundary types, and normalized agent-event projection across stores, workflow providers, workspace providers, and agent runners. It depends on interfaces, not concrete providers.
- `SymphonySync`: provider-neutral sync outbox/cloud exchange processing and conflict resolution policy with transport and store protocols.
- `ComposerApp`: the SwiftUI macOS board and inspector.
- `ComposerCLI`: the `composerctl` command-line surface for writing projects and tasks into the selected local store backend.
- `ComposerRuntimeHelper`: the LaunchAgent-hosted helper that exposes runtime service calls over XPC.

## Development

Use the Makefile as the main developer entry point:

| Command | Description |
| --- | --- |
| `make test` | Build and run tests |
| `make build` | Build the CLI and macOS app |
| `make helper` | Build `composer-runtime-helper` |
| `make install-helper` | Install and bootstrap the runtime LaunchAgent |
| `make unload-helper` | Boot out the runtime LaunchAgent |
| `make xcode-build` | Build `Composer.app` with Xcode |
| `make app` | Build and open `Composer.app` |
| `make open-project` | Open `Composer.xcodeproj` in Xcode |
| `make cli` | Install `composerctl` to `~/.local/bin` |
| `make smoke-cli` | Run a CLI smoke test against a temporary store |
| `make smoke-cli-sqlite` | Run a CLI smoke test against a temporary SQLite store |

The SwiftUI app is launched through the checked-in Xcode project so macOS receives a normal `.app` bundle. SwiftPM remains the package boundary for shared libraries, tests, and the CLI.

After installing the CLI:

```sh
make cli
composerctl help
```

Examples:

```sh
composerctl project add --name Composer --repo /path/to/repo --agent codex
composerctl task add --project Composer --title "Add workflow loader" --state ready --priority high --label workflow --agent claude --model sonnet --agent-param effort=high
composerctl task list --project Composer
composerctl task move --task LOCAL-1 --state human-review --project Composer
composerctl --store-backend sqlite --store /tmp/composer.sqlite3 task list
```

The app defaults to the JSON store. For launch-time backend selection, set:

```sh
COMPOSER_STORE_BACKEND=sqlite COMPOSER_STORE_PATH=/tmp/composer.sqlite3 .build/XcodeDerivedData/Build/Products/Debug/Composer.app/Contents/MacOS/Composer
```

The same values can also be stored in app defaults with `ComposerStoreBackend` and `ComposerStorePath`.

The runtime helper can be built and installed locally:

```sh
make helper
make install-helper
```

It registers the `dev.janneh.composer.runtime` Mach service and uses the same `COMPOSER_STORE_BACKEND` / `COMPOSER_STORE_PATH` environment keys when launched directly.

To route app runtime actions through the helper, launch the app with:

```sh
COMPOSER_RUNTIME_MODE=helper .build/XcodeDerivedData/Build/Products/Debug/Composer.app/Contents/MacOS/Composer
```

The app also reads `ComposerRuntimeMode` and `ComposerRuntimeMachService` from app defaults.
