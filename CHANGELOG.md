# Changelog

## Unreleased — 0.1.0 development

Initial independently versioned repository. This is not a stable or production release.
See the implementation checklist for feature status and verification limits.

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
