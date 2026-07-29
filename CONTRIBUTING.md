# Contributing

Thanks for helping improve Glosslet.

## Development

Glosslet is a Swift Package targeting macOS 14 and later. Xcode's command-line
tools are sufficient for normal development.

```bash
swift test --parallel
scripts/build_app.sh release
```

Before opening a pull request, run:

```bash
scripts/check.sh
```

To inspect every transcript style without creating a Codex task, build the app
and launch its deterministic rendering preview:

```bash
scripts/build_app.sh release
open dist/Glosslet.app --args --render-preview
```

Live integration tests are deliberately opt-in because they use the signed-in
Codex account and create a persistent task:

```bash
GLOSSLET_RUN_CODEX_INTEGRATION=1 \
  swift test --filter CodexAppServerIntegrationTests
```

## Pull requests

- Keep changes focused and explain user-visible behavior.
- Add or update tests for protocol and selection logic.
- Do not add telemetry, a separate authentication flow, or a parallel chat
  database.
- Preserve the invariant that every Glosslet-created thread is persistent and
  discoverable in the Codex app.
- Never log selected text, follow-up content, credentials, or approval payloads.
- Keep transcript assets local and update
  [Third-party notices](THIRD_PARTY_NOTICES.md) when a bundled renderer changes.

By contributing, you agree that your contribution is licensed under the MIT
License.
