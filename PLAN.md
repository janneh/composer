# Composer Implementation Plan

Composer is a native macOS control plane for Symphony-style coding-agent orchestration. The app should stay local-first while keeping every important boundary generic enough to swap implementations later.

## Product Shape

- Native macOS app with a kanban board, task inspector, runtime dashboard, and review queue.
- Companion CLI for adding and moving projects/tasks from terminals or agent sessions.
- Local tracker first, cloud/team sync later.
- Generic orchestration core that can run Codex, Claude, Gemini, or future coding agents.
- Generic tracker/storage interfaces so local SQLite, Linear, GitHub Issues, and a hosted backend can share the same app/runtime model.

## Architecture Principles

- The UI depends on application models and protocols, not concrete providers.
- The orchestrator depends on generic ports: task store, tracker, workflow provider, workspace provider, agent runner, event sink.
- Runtime events are normalized across agent providers.
- User-visible mutations should be event-shaped so sync can be added later.
- Storage should be replaceable without changing UI or orchestration logic.
- Agent integrations should live in separate packages with provider-specific parsing and process control isolated there.

## Package Layout

- `SymphonyCore`: provider-neutral models and identifiers.
- `SymphonyInterfaces`: storage, tracker, workflow, workspace, agent, sync, and event protocols.
- `SymphonyLocalStore`: local JSON store; useful for demo/test storage and external file-change streaming.
- `SymphonySQLiteStore`: durable local store with migrations, indexed queries, and JSON payload preservation.
- `SymphonyWorkflow`: `WORKFLOW.md` discovery/loading, front matter parsing, selected-project UI diagnostics, and prompt rendering.
- `SymphonyWorkspace`: planned worktree/workspace lifecycle and cleanup policy.
- `SymphonyAgents`: planned shared runner protocol support types if `SymphonyInterfaces` grows too large.
- `SymphonyCodexAgent`: planned Codex app-server runner.
- `SymphonyClaudeAgent`: planned Claude CLI/Agent SDK runner.
- `SymphonyGeminiAgent`: planned Gemini runner.
- `SymphonyRuntime`: orchestration state machine and dispatch logic.
- `ComposerApp`: SwiftUI macOS app surface.
- `ComposerCLI`: command-line insertion and editing surface backed by the same local store.

## Roadmap

### 1. Local Board MVP

- [x] SwiftPM package scaffold.
- [x] Generic domain models.
- [x] Generic protocol interfaces.
- [x] Local JSON-backed store.
- [x] Initial kanban board and inspector.
- [x] Editable task detail.
- [x] Task dependency editor.
- [x] Runtime event list in inspector.
- [x] CLI project/task creation and task movement.
- [x] Makefile developer commands.
- [x] UI project creation and settings.
- [x] Stream local store changes into the UI.
- [x] Dispatch preview UI.
- [x] Xcode project for launching the macOS app bundle.

### 2. Durable Local Storage

- [x] Add `SymphonySQLiteStore`.
- [x] Add initial schema migration.
- [x] Add tested storage backend factory.
- [x] Wire `composerctl` to JSON/SQLite backend selection.
- [x] Wire `ComposerApp` to JSON/SQLite backend selection.
- [ ] Add append-only event log.
- [ ] Add sync metadata tables.
- [ ] Add full-text search indexes.

### 3. Workflow And Workspace

- [x] Add `WORKFLOW.md` loader.
- [x] Parse workflow config/front matter.
- [x] Validate workflow diagnostics in UI.
- [x] Render prompts from project/task/run context.
- [ ] Prepare per-task workspace/worktree.
- [ ] Track workspace path and cleanup policy.

### 4. Agent Runtime

- [ ] Add normalized agent event model coverage for tool use, partial output, completion, failures, and input requests.
- [ ] Add Codex runner.
- [ ] Add Claude runner.
- [ ] Add Gemini runner.
- [ ] Add per-task agent selection and provider settings.
- [ ] Add cancellation, retry, stall detection, and resume support.

### 5. Background Execution

- [ ] Split runtime composition from SwiftUI app lifecycle.
- [ ] Add XPC boundary.
- [ ] Add helper/LaunchAgent process.
- [ ] Keep active runs alive when the main window closes.

### 6. Sync And External Trackers

- [ ] Define sync outbox processor.
- [ ] Add conflict resolution policy.
- [ ] Add cloud transport boundary.
- [ ] Add Linear tracker implementation.
- [ ] Add GitHub Issues tracker implementation.

## Current Focus

Add `WORKFLOW.md` loading/parsing so tasks can become executable agent inputs rather than only trackable records.
