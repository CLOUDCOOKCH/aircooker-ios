# Native implementation status

The Swift core is compiled and tested on Linux using Swift 6.2.1. Earlier runs used Docker;
see VALIDATION.md for the final host-toolchain recovery and its exact limits. SwiftUI, UIKit,
VisionKit, WidgetKit, LocalAuthentication, Keychain and notifications have not been compiled
or tested with an Apple SDK here. All native UI functionality is therefore unverified.

Implemented sources: adaptive native tint, shared recipe/meal presentation, photo-led recipe grid,
interactive civil-date Home week selection, focused daily meal presentation, shared searchable
Home/Calendar assignment and grouped settings; Home meal hierarchy and empty-state actions, clearer calendar date/week controls; five-tab navigation, HTTPS onboarding, QR scanner, initial setup/login,
Keychain token vault with generation-checked sign-out and durable revocation, optional local access lock, persistent SQLite/outbox, server identity
pinning, sync, recipe list/detail/editor/scaling and photo selection/cache, week calendar assignment,
occurrence-aware movement/duplication, day/week copy previews, template save/apply, recurrence editing,
accessible context-menu alternatives, pantry editing, leftover recording/editing/discard/assignment,
local suggestion preferences/review/selection, import queue/review sources, App Group
share inbox, 14-day widget snapshots/timeline sources, deferred deep links, reminder preferences
opt-in notification reconciliation, rejected-change review and saved local draft recovery, explicit server-history rebuild, durable snapshot staging and reauthentication. English/German resources are present.

Tested core: prepared photo + recipe + outbox atomic persistence, upload-before-recipe sync,
replay after lost responses/restart, photo cache, v1→v2 local migration, bounded recurrence,
exceptions, detached movement, civil dates, template validation, atomic copy batches,
leftover reservation invariants, local recommendations, stale-preview checks, atomic approval,
reminder dates/DST/grouping/limits, strict deep-link parsing and widget rollover/privacy/expiry;
per-entity rejection isolation, server snapshots, atomic archive/copy recovery, stale-decision
guards, coordinator exclusion and schema-v3 migration replay; schema-v4 history proofs,
resumable full rebuild, final archive/projection rollback and restored media requeue; read-only planner overview boundaries, recurrence, unique-slot counts and
selected-day ordering; persisted credential envelopes, late refresh/login rejection, offline
revocation retry and draft/outbox preservation during sign-out.

Remaining: full native SDK build/Swift concurrency validation; photo quota/cleanup UI;
arbitrary copy destinations, native leftover/suggestion lifecycle validation, shared household
recommendation preferences and cross-device approval collision handling; import preview lifecycle
end-to-end; provider disclosure/configuration; Apple notification delivery/permission and
widget/deep-link lifecycle validation; native logout/session revocation lifecycle and deletion UX; recoverable sync
recovery UI/device validation and reference-safe restoration beyond recipes; UI tests; app icon; screenshots; demo environment; TestFlight signing/upload;
accessibility audit; full performance/privacy/security validation.

The server repository's implementation checklist tracks the full product phases. Neither
repository is declared complete, production-ready or App Store-ready. No remote repository
or release has been published. Intended owner: CLOUDCOOKCH.
