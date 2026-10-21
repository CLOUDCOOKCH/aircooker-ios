# Native implementation status

The Swift core is compiled and tested on Linux using Swift 6.2.1. Earlier runs used Docker;
see VALIDATION.md for the final host-toolchain recovery and its exact limits. SwiftUI, UIKit,
VisionKit, WidgetKit, LocalAuthentication, Keychain and notifications have not been compiled
with an Apple SDK in this Linux workspace. GitHub Xcode 26.6 has now built the app and
extensions at e82cae4; simulator installation exposed missing extension display names,
which were fixed. Foundation run 39560965568 at 528a9ac passes native build, simulator
onboarding, core and secret checks. Demo run 39563358861 at 17b1318 passes 85 core tests on both platforms and builds all
three native targets. Its UI step stopped during simulator system-data migration before
XCTest; the bounded first-boot deadline has been increased for the next run.

Implemented sources: adaptive native tint, shared recipe/meal presentation, photo-led recipe grid,
interactive civil-date Home week selection, focused daily meal presentation, shared searchable
Home/Calendar assignment and grouped settings; saved recipe card/list layout, adaptive rating
metadata and calendar-linked weekly summary with Reduce Motion support; native Liquid Glass
controls, photo category overlay and accessibility surface fallbacks; Home meal hierarchy
and empty-state actions, clearer calendar date/week controls; five-tab navigation, HTTPS onboarding, QR scanner, initial setup/login,
Keychain token vault with generation-checked sign-out and durable revocation, optional local access lock, persistent SQLite/outbox, server identity
pinning, sync, recipe list/detail/editor/scaling and photo selection/cache, week calendar assignment,
occurrence-aware movement/duplication, day/week copy previews, template save/apply, recurrence editing,
accessible context-menu alternatives, pantry editing, leftover recording/editing/discard/assignment,
local suggestion preferences/review/selection, import queue/review sources, App Group
share inbox, 14-day widget snapshots/timeline sources, deferred deep links, reminder preferences
opt-in notification reconciliation, rejected-change review and saved local draft recovery, explicit server-history rebuild, durable snapshot staging and reauthentication. English/German resources are present. The isolated offline demo includes atomic sample
seeding, persistent editing, explicit service limitations and a visible sample-data notice;
85 portable tests pass, including five new demo isolation/restart/rollback tests.

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

Remaining: complete native lifecycle/Swift concurrency validation; photo quota/cleanup UI;
arbitrary copy destinations, native leftover/suggestion lifecycle validation, shared household
recommendation preferences and cross-device approval collision handling; import preview lifecycle
end-to-end; provider disclosure/configuration; Apple notification delivery/permission and
widget/deep-link lifecycle validation; native logout/session revocation lifecycle and deletion UX; recoverable sync
recovery UI/device validation and reference-safe restoration beyond recipes; expanded UI tests; icon appearance validation; genuine screenshot review; demo native
acceptance; TestFlight signing/upload;
accessibility audit; full performance/privacy/security validation.

The server repository's implementation checklist tracks the full product phases. Neither
repository is declared complete, production-ready or App Store-ready. Both independent
repositories are published under CLOUDCOOKCH; no stable release has been published. The
first GitHub run passed core tests/secret scanning but stopped before native compilation
because the runner had Xcode 26.6 rather than the previously hard-coded version 27.
CI now checks actual iOS 26+ capability; the foundation native run passes as recorded
above. Current demo UI acceptance remains open.
