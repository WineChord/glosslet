# Changelog

All notable changes to Glosslet will be documented in this file.

## 0.2.7 — 2026-08-01

- Reuses the authenticated persistent Codex App Server control socket when it
  is available, while retaining the standalone Codex executable as a fallback.
- Checks the live Codex account before the first model request so authentication
  failures are reported immediately instead of surfacing as a late `401`.
- Made cross-app selection lookup more resilient to macOS focused-application
  timing and added a privacy-safe selection diagnostic for troubleshooting.
- Added a durable permission monitor shared by onboarding, Settings, the menu
  bar, and selection handling, so Accessibility changes are reflected without
  restarting Glosslet.
- Made the successful setup state explicit and clarified that closing the
  window leaves Glosslet running in the menu bar.
- Restores the main window whenever an already-running Glosslet is opened
  again, and temporarily shows the app in the Dock while setup or Settings is
  visible.
- Added a scoped repair action that resets only Glosslet's stale Accessibility
  entry before reopening the correct macOS settings page.
- Signed release assets with a stable project identity so later updates can
  preserve Accessibility authorization after the one-time v0.2.7 migration.
- Added an automated, identity-verified GitHub tag release workflow.

## 0.2.6 — 2026-07-31

- Removed Glosslet's app-level 32k proactive-compaction threshold and its
  background maintenance state so Codex remains the sole owner of context
  compaction and rollover.
- Sends explanations and follow-ups directly to the reused persistent task
  without waiting for a Glosslet-scheduled maintenance turn.
- Keeps native context-management events compatible with the floating status
  display without treating the entire response turn as maintenance output.
- Reworked the live integration check to verify two-turn context continuity on
  one persistent Codex task without manually requesting compaction.

## 0.2.5 — 2026-07-31

- Replaced the in-layout configuration drawer with a floating overlay so model
  and reasoning menus no longer push or compress the conversation transcript.
- Removed the competing move, opacity, content-morph, and header-size
  animations in favor of one short scale-and-fade transition.
- Swaps directly between model and reasoning content without cross-animating
  different drawer heights, and rotates one stable chevron instead of replacing
  symbols.
- Added restrained press feedback and click-away dismissal inside the panel.

## 0.2.4 — 2026-07-31

- Prewarmed the saved Codex task, skill catalog, hooks, and MCP metadata at app
  launch so deterministic setup no longer blocks the first visible request.
- Used the latest model's advertised priority service tier together with the
  existing lowest-reasoning policy; the model picker now discloses its increased
  usage.
- Added idle, same-task context compaction based on Codex token-usage events so
  a long-running fixed task stays responsive without losing its ID or visible
  history.
- Coalesced fixed-task attachment and model discovery across simultaneous
  startup and selection requests.
- Shortened the initial explanation envelope while preserving quoted-selection
  isolation, language adaptation, technical notation, and read-only behavior.
- Added a live integration check for priority routing, native compaction,
  persistent continuation, and automatic cleanup of its disposable task.

## 0.2.3 — 2026-07-31

- Kept the active Codex task and app-server connection warm between Glosslet
  turns instead of restarting them before every request.
- Coalesced simultaneous startup and model-catalog requests onto one Codex
  app-server connection.
- Reloaded persistent history only after the Codex app may have changed the
  task from another process.
- Split connection, task-refresh, thinking, and response-writing activity into
  accurate stages with live elapsed time and final request duration.
- Removed the clipped rectangular shadow around the rounded selection toolbar.
- Added deterministic toolbar previewing and optional Developer ID signing and
  notarization support for release builds.

## 0.2.2 — 2026-07-30

- Latched the toolbar anchor when a selection is first observed so passive
  polling and later pointer movement cannot reposition it.
- Kept selection identity stable when an app exposes text and range geometry
  at different times.
- Prevented later mouse-up events on an unchanged selection from replacing its
  original placement anchor.

## 0.2.1 — 2026-07-30

- Anchored the selection toolbar to the mouse-selection endpoint or
  Accessibility insertion point instead of the full selection rectangle.
- Rejected zero-sized Accessibility geometry and added screen-safe fallbacks.
- Added model and reasoning-effort controls directly to the conversation panel.
- Refined the header, configuration drawer, transcript rhythm, and composer
  around a consistent layout grid.
- Kept click-away dismissal compatible with in-panel configuration controls.
- Added live Accessibility-status refresh, a direct Settings deep link, and
  recovery guidance for stale permissions after an ad-hoc rebuild.

## 0.2.0 — 2026-07-30

- Added offline Markdown, table, task-list, code-highlight, and LaTeX rendering.
- Added one-click copying for fenced code blocks.
- Added default click-away dismissal and an explicit pin control.
- Refined the conversation shell, composer, toolbar, status, and window chrome.
- Reworked the app and menu-bar marks with a quieter monochrome identity.
- Added a deterministic rendering preview and packaged-resource validation.

## 0.1.0 — 2026-07-29

- Added cross-app Accessibility selection detection.
- Added the two-action Explain and Copy floating toolbar.
- Added streaming Codex explanations and follow-up conversations.
- Added persistent, Codex-app-visible task creation and fixed-task reuse.
- Added cross-process history refresh for genuine two-way Codex App continuity.
- Added dynamic latest-model and lowest-reasoning selection.
- Added Codex defaults and custom model modes.
- Added approvals, stop, exact-task deep links, onboarding, and settings.
- Added bilingual English and Simplified Chinese interface copy.
- Added a universal Apple silicon and Intel app build.
- Added release bundling, CI, tests, privacy documentation, and app icon.
