# Composer Agent Workflow

You are working in the Composer repository on {{ issue.identifier }}: {{ issue.title }}.

Composer is a local-first macOS control plane for coding-agent orchestration. Keep changes provider-neutral unless the task explicitly targets a provider package.

## Task

{{ issue.description }}

## Rules

- Read the surrounding code before editing.
- Keep UI code in `ComposerApp` focused on presentation and move provider or runtime behavior behind package boundaries.
- Keep concrete storage, tracker, and agent integrations behind protocols.
- Prefer small vertical changes that compile.
- Use existing design tokens and primitives for UI work.
- Run the narrowest useful build or test command before finishing.

{% if attempt %}This is retry attempt {{ attempt }}. Address the previous failure directly and keep the change scoped.{% endif %}
