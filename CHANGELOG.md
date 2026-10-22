# Changelog

- Deliberately refresh the canonical v1 server contract pin for optional image imports
  and the typed reviewed-import response. Recipe/Ingredient input/output schema names
  reflect FastAPI decimal serialization. Review earlier additive optional planning-export,
  pantry week-override and suggestion-checkpoint fields; the checker explicitly verifies
  optional compatibility while retaining exact required native wire checks.
  Camera/OCR UI ships in the primary PWA; no native UI feature is claimed by this pin.

- Make simulator keyboard setup explicit and wait for keyboard readiness before demo
  recipe/search text entry. The mealf build/core checks passed; the prior UI run exposed
  missing input focus and requires a new verified simulator run.

- Adopt the mealf product name in app/Share/widget display names and English/German copy.
  Retain bundle IDs, Keychain, App Groups, database paths and build targets so this name-only
  change does not strand existing installations. New supplied artwork awaits original files.

## Unreleased — 0.1.0 development

- Record the user-confirmed PWA-first delivery decision; preserve native code for later.
  No Swift code, pinned contract or Apple capabilities are changed by this documentation.

- Display existing ingredient preparation notes and source-attributed nutrition in recipe
  details; nutrition stays as supplied and is not guessed or rescaled.

Initial independently versioned repository. This is not a stable or production release.
See the implementation checklist for feature status and verification limits.

- Normalise manual ingredient fractions, ranges and decimal commas before offline save;
  show invalid amounts inline and preserve unmeasured phrases without multiplying them.
- Add five quantity/recipe persistence tests and pin the additive server diagnostics
  contract; existing native resource and sync wire schemas remain unchanged.

- Add an explicit offline demo with a separate database/identity and original illustrative
  food artwork; household data, credentials and pending edits are never reused for samples.
- Add five atomic-seed/isolation/restart tests and native demo persistence/localisation
  workflows with light/dark captures. Demo recipe restart/search/exit, onboarding and German light/dark UI checks pass on iOS 26.5.

- Publish both repositories and begin real GitHub backend/browser/core/native CI checks.
- Check the installed supported Apple SDK instead of requiring an unavailable Xcode version.
- Add original icon artwork with reproducible Apple asset preparation and the app's
  required-reason UserDefaults privacy manifest. Native validation remains in progress.

- Use native Liquid Glass for planning controls, over-photo labels, create/suggestion
  actions and sync notices, with opaque custom-surface accessibility fallbacks.
- Keep the native tab bar; disable scroll minimisation for Reduce Motion/accessibility
  text sizes. Apple SDK and device validation remain required.

- Add a remembered recipe Cards/List choice and shared compact rows with actual ratings.
- Make the weekly summary open its calendar, distinguish the selected week from this week,
  and respect Reduce Motion for count transitions. Native SDK/rendering validation pending.

- Persist prepared recipe photos with recipe edits and the outgoing queue atomically;
  upload before recipe sync and keep a durable offline photo cache.
- Add native system photo selection and local recipe image views (Apple SDK unverified).
- Add bounded local recurrence, exception-aware moves/removal, day/week copy previews,
  weekly templates and atomic local edit batches, with 24 core tests.
- Expand English/German resources and pin the server media API contract.

- Add offline leftover recording, reserved/unplanned portion editing, discard and calendar
  assignment with shared validation of portion limits and preparation dates.
- Add local weekly suggestions using ratings/history, recurrence and available leftovers;
  explicit selection and snapshot-checked approval preserve existing plans.
- Add native leftover/suggestion interfaces and English/German strings (Apple SDK unverified).
- Verify Python/Swift recommendation equivalence with a pinned canonical fixture.

- Add household-zone reminder planning with recurrence, cooked-meal suppression, grouped
  slots, DST rules and chronological scheduling limits.
- Wire opt-in native reminder settings/reconciliation and notification tap routes.
- Replace the single-day widget file with a bounded 14-day timeline cache, expiry and
  optional recipe-name privacy; add deferred read-only app links and calendar targeting.
- Clear derived widget/reminder state on logout while preserving offline edits; persist
  signed-out state across restart. Apple framework/runtime verification remains pending.

- Pin the additive backend administration contract, including redacted AI settings, storage
  summaries and current-session metadata; validate the exact source commit and checksum.

- Keep rejected offline changes per entity while allowing unrelated records and deltas to
  synchronise. Preserve durable server snapshots alongside unsent local edits.
- Archive all queued edits before accepting server state or copying a recipe to a fresh
  identity; guard stale review decisions and in-flight sync/recovery races.
- Add native English/German recovery/archive/sharing controls; platform validation pending.
- Migrate the local store to schema 3 without losing outbox identities or cached photos.

- Detect restored/divergent server history with persistent commit proofs, including receipts
  acknowledged before the next delta pull; protect preflight-to-request races.
- Add explicitly confirmed, durable full-resync staging and atomic archive/projection
  replacement, preserving queued edits, acknowledged cached records and photo bytes.
- Requeue media and detach one-time import confirmation when restoring recipe copies.
- Add native recovery/continue/sign-in controls and English/German strings; native SDK
  validation remains pending.

- Add generation-checked credentials and a durable Keychain revocation queue; retain offline
  drafts/outbox on sign-out and retry pending server revocation on launch/foreground/manual retry.
- Prevent late refresh/login responses from restoring signed-out authentication; upgrade
  legacy token-only envelopes and reject unknown formats without clearing secure storage.
- Add English/German pending sign-out controls; native Apple validation remains outstanding.
- Prefer unused recipes before repeats regardless of extreme rating/history differences.

- Refine Home into meals, planning and recipe sections; keep import/create actions available.
- Add adaptive photo-led recipe cards, meaningful empty states, shared native surfaces and
  light/dark tint assets. Improve calendar date/week hierarchy and accessible meal actions.
- Preserve cached photo presentation during reload; native rendering remains unverified.

- Add interactive Home week/day selection, a featured planned meal and truthful slot counts
  from cached data. Reuse one searchable offline recipe/leftover picker across Home/Calendar.
- Group settings by preferences, sync/recovery and server connection; keep native type,
  adaptive layout and direct secure console access. Native Apple validation remains open.

## Mealf native identifiers — 2026-10-22

- Rename Swift module/package, app/extension/test targets, URL scheme, bundle IDs, App Group and current development tooling to Mealf. Provision the new identifiers and install a fresh development build; PWA data is unaffected.
- Pin the reviewed server contract at 753e1ff, using current Mealf sync headers.
- Preserve optional imported recipe and ingredient metadata during decode/edit/encode, with a round-trip regression test. Native UI parity for the newer web imports remains future work.
