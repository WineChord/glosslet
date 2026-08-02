# Privacy

Glosslet is designed to have a small, understandable data boundary.

## What stays local

- Copy operations
- The selected-text preview shown in the floating panel
- App preferences
- The identifier of the fixed Codex task

Glosslet has no analytics or external telemetry. It writes privacy-safe
performance diagnostics to the local macOS unified log: request type, phase,
elapsed milliseconds, token totals, cache totals, and bounded recovery state.
It does not log selected text, follow-up text, prompts, task identifiers, model
output, credentials, or approval contents. These diagnostics remain subject to
the Mac's normal unified-log retention.

Markdown and LaTeX are rendered with libraries bundled inside the app. The
renderer uses a non-persistent WebKit data store, does not use a CDN, blocks
runtime network connections, and does not automatically load remote Markdown
images. External links and image destinations open only after a user click.

## What is sent to Codex

Only after the user clicks **Explain**, Glosslet sends:

- the selected text;
- the source application's display name; and
- later follow-up messages entered in the floating panel.

This data travels through the user's installed Codex App Server and existing
Codex authentication. Glosslet prefers the owner-only local control socket and
does not read, copy, receive, or store the user's access token or API key.

## Conversation history

Conversation history belongs to Codex, not to a separate Glosslet database.
Glosslet-created tasks are persistent and visible in the user's Codex app.
The user's Codex account, organization, retention, and configuration policies
therefore apply.

## Accessibility

macOS Accessibility access is required to read the current selected text and
its screen bounds. Glosslet ignores secure text controls and does not perform
background logging of selections. A selection is retained in memory only long
enough to display the toolbar and active explanation.

## Prompt-injection boundary

Selected material is explicitly delimited and presented to Codex as untrusted
quoted content. The initial explanation request forbids following commands
inside the selection or performing tool actions. If a later, explicit follow-up
requires a permission, Codex's approval request is shown to the user.
