# Composer

Composer is a native macOS control surface for Symphony-style agent orchestration.

The first implementation keeps the important boundaries generic:

- `SymphonyCore`: provider-neutral domain models for projects, work items, runs, agents, and runtime events.
- `SymphonyInterfaces`: protocol boundaries for storage, trackers, workflow loading, workspaces, agent runners, sync, and event sinks.
- `SymphonyLocalStore`: a local JSON-backed store used by the initial app. SQLite can replace this behind the same protocols.
- `SymphonyRuntime`: the orchestration state-machine skeleton. It depends on interfaces, not concrete stores or agents.
- `ComposerApp`: the SwiftUI macOS board and inspector.

Run tests with:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
  swift test --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache"
```

Run the app with:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
  swift run --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache" Composer
```

Use the CLI with:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
  swift run --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache" composerctl help
```

Examples:

```sh
composerctl project add --name Composer --repo /path/to/repo --agent codex
composerctl task add --project Composer --title "Add workflow loader" --state ready --priority high --label workflow
composerctl task list --project Composer
composerctl task move --task LOCAL-1 --state human-review --project Composer
```
