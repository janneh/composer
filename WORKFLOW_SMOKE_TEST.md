# Workflow Smoke Test

This guide exercises the local Composer workflow with a tiny Todo web app. It verifies that Composer can load `WORKFLOW.md`, render task context into the workflow prompt, create an isolated worktree, dispatch a real agent through the runtime helper, and record completion events back into the app.

## What This Tests

- Project and task creation through `composerctl`.
- SQLite-backed app and CLI storage sharing.
- `WORKFLOW.md` loading and strict template rendering.
- Runtime helper dispatch.
- Workspace creation through Git worktrees.
- Agent execution against the generated workspace.
- Runtime event streaming back into Composer.

## Create A Tiny Todo Repository

```sh
TODO_REPO=/tmp/composer-todo-smoke
STORE=/tmp/composer-todo-smoke.sqlite3

rm -rf "$TODO_REPO" "$STORE"
mkdir -p "$TODO_REPO"
cd "$TODO_REPO"

git init
git config user.name "Composer Smoke Test"
git config user.email "composer@example.local"

cat > README.md <<'EOF'
# Todo Smoke App

A tiny static Todo web app.
EOF

cat > WORKFLOW.md <<'EOF'
You are working on {{ issue.identifier }}: {{ issue.title }}.

Build the requested feature in this repository.

Rules:
- Keep it simple.
- Prefer plain HTML, CSS, and JavaScript.
- Do not install dependencies unless the task explicitly requires it.
- Make the app usable by opening index.html in a browser.
- After changes, summarize what files changed.

Task description:
{{ issue.description }}

{% if attempt %}This is attempt {{ attempt }}. Fix the previous issue and keep moving.{% endif %}
EOF

git add .
git commit -m "Initial todo smoke app"
```

## Add The Project And Task To Composer

Install the CLI if needed:

```sh
make cli
```

Create a Composer project that points at the Todo repository:

```sh
composerctl \
  --store-backend sqlite \
  --store "$STORE" \
  project add \
  --name "Todo Smoke" \
  --repo "$TODO_REPO" \
  --agent codex
```

Create one Ready task:

```sh
composerctl \
  --store-backend sqlite \
  --store "$STORE" \
  task add \
  --project "Todo Smoke" \
  --identifier TODO-1 \
  --title "Build a simple Todo web app" \
  --description "Create index.html, styles.css, and app.js. Users should be able to add todos, mark them complete, delete them, and persist them in localStorage." \
  --state ready \
  --priority high \
  --label smoke \
  --label web
```

Confirm the task is ready:

```sh
composerctl \
  --store-backend sqlite \
  --store "$STORE" \
  task list \
  --project "Todo Smoke" \
  --state ready
```

## Launch Composer In Helper Mode

Real agent execution currently goes through the runtime helper. Install and launch it:

```sh
make install-helper
```

Open the app against the same SQLite store:

```sh
COMPOSER_STORE_BACKEND=sqlite \
COMPOSER_STORE_PATH="$STORE" \
COMPOSER_RUNTIME_MODE=helper \
make app
```

In the app:

1. Select `Todo Smoke`.
2. Confirm `TODO-1` appears in `Ready`.
3. Click `Dispatch Preview`.
4. Confirm the task is listed as ready to run.
5. Click `Dispatch Ready`.
6. Watch the task move to `Running`, then `Human Review` or `Failed`.
7. Open the task inspector to inspect runtime events.

## Inspect The Generated Workspace

Composer runs agents in a Git worktree, not directly in the source repository. Find the worktree:

```sh
git -C "$TODO_REPO" worktree list
```

The Composer worktree should be under:

```sh
~/.composer/workspaces/
```

Inspect the generated Todo app files in that worktree. For this task, a successful run should usually create or update:

- `index.html`
- `styles.css`
- `app.js`

You can open the app directly in a browser from the generated worktree:

```sh
open /path/to/generated/worktree/index.html
```

## Expected Result

A passing smoke test demonstrates that:

- Composer and `composerctl` are using the same durable store.
- `WORKFLOW.md` was loaded from the project repository.
- Template fields such as `{{ issue.identifier }}` and `{{ issue.description }}` rendered into the prompt.
- The runtime helper started the selected agent.
- Composer created a task-specific workspace.
- Agent events streamed back into Composer.
- The task reached `Human Review` on success or `Failed` with an inspectable error.

If dispatch fails, first inspect the task events in the Composer inspector. Common failures are missing agent CLIs on `PATH`, a non-Git repository path, or helper mode not pointing at the same store as the app.
