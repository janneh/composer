# Composer

Composer is a native macOS control surface for Symphony-style agent orchestration.

It is inspired by OpenAI's [Symphony orchestration spec](https://github.com/openai/symphony/blob/main/SPEC.md).

Licensed under the [Apache License 2.0](LICENSE).

The first implementation keeps the important boundaries generic:

- `SymphonyCore`: provider-neutral domain models for projects, work items, runs, agents, and runtime events.
- `SymphonyInterfaces`: protocol boundaries for storage, trackers, workflow loading, workspaces, agent runners, sync, and event sinks.
- `SymphonyLocalStore`: a local JSON-backed store used by the initial app. SQLite can replace this behind the same protocols.
- `SymphonySQLiteStore`: a durable SQLite-backed store with versioned schema setup, indexed queries, and JSON payload preservation.
- `SymphonyRuntime`: the orchestration state-machine skeleton. It depends on interfaces, not concrete stores or agents.
- `ComposerApp`: the SwiftUI macOS board and inspector.
- `ComposerCLI`: the `composerctl` command-line surface for writing projects and tasks into the same local store.

## Development

Use the Makefile as the main developer entry point:

| Command | Description |
| --- | --- |
| `make test` | Build and run tests |
| `make build` | Build the CLI and macOS app |
| `make xcode-build` | Build `Composer.app` with Xcode |
| `make app` | Build and open `Composer.app` |
| `make open-project` | Open `Composer.xcodeproj` in Xcode |
| `make cli` | Install `composerctl` to `~/.local/bin` |
| `make smoke-cli` | Run a CLI smoke test against a temporary store |

The SwiftUI app is launched through the checked-in Xcode project so macOS receives a normal `.app` bundle. SwiftPM remains the package boundary for shared libraries, tests, and the CLI.

After installing the CLI:

```sh
make cli
composerctl help
```

Examples:

```sh
composerctl project add --name Composer --repo /path/to/repo --agent codex
composerctl task add --project Composer --title "Add workflow loader" --state ready --priority high --label workflow
composerctl task list --project Composer
composerctl task move --task LOCAL-1 --state human-review --project Composer
```
