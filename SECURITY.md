# Security Policy

## Supported versions

Security fixes are applied to the latest release.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability that could expose
selected text, Codex credentials, local files, or approval decisions. Use
GitHub's private vulnerability reporting for this repository.

Include the affected version, macOS version, reproduction steps, and expected
impact. Avoid including real credentials or private selected text.

## Security model

- Glosslet reads the current selection through macOS Accessibility.
- Secure text fields are excluded.
- Copy never leaves the Mac.
- Explain sends the selection through the user's installed Codex app server.
- Glosslet does not collect telemetry, store API keys, or maintain a separate
  conversation database.
- Selected material is wrapped as untrusted quoted content so embedded text is
  not treated as an instruction.
- Codex approval requests remain user-visible in the floating conversation.
