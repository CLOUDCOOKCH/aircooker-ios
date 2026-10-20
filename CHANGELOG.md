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
