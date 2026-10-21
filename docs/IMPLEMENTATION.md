# Native implementation status

**API contract refresh, 2026-10-21:** deliberately pinned server c97bf16 for the
primary PWA’s image-import extension and typed import response. Reviewed the existing
optional planning-export, pantry override and suggestion-checkpoint additions since the
previous native pin; exact native field checks and optional compatibility checks pass.
Native photo/OCR import UI is not added by this contract-only refresh. Local contract and
296-key localisation checks pass. CI 39660428236 at 32604a1 passes both jobs: 90 core
tests on Linux/macOS, Xcode 26.6 builds all native targets, and the existing onboarding/demo
and German light/dark simulator flows pass. This validates the retained client against
the pinned contract, not new native camera/OCR UI or physical hardware. See
validation/github-image-import-contract.json.

**Brand update, 2026-10-21:** the product is now mealf. App/Share/widget display names,
onboarding and English/German copy are updated; bundle IDs, App Groups, Keychain, paths and
build targets remain compatible. The original supplied peach icon/wordmark PNG files are
not accessible in the cloud workspace, so their installation is still pending. Native
development remains retained for later. Name/keyboard source at 805d043 passed Xcode 26.6,
90 core tests and simulator flows in run 39590881768; physical devices/artwork remain open.

Delivery direction changed to PWA-first by explicit user choice on 2026-10-21. Native
feature development is paused; keep the tested sources available for later. The web client
is implemented in the independent aircooker-server repository, not in a third repository.
Native signing/TestFlight/device gates remain deferred and are not considered PWA blockers.
The latest native source validation at 805d043 passes 90 core tests, all three native targets,
and demo/onboarding/localisation simulator workflows on Xcode 26.6 (run 39590881768).
See validation/github-mealf-name.json for exact evidence and the preceding UI failure.
The historical evidence below retains its original scope.

The Swift core is compiled and tested on Linux using Swift 6.2.1. Earlier runs used Docker;
see VALIDATION.md for the final host-toolchain recovery and its exact limits. SwiftUI, UIKit,
VisionKit, WidgetKit, LocalAuthentication, Keychain and notifications have not been compiled
with an Apple SDK in this Linux workspace. GitHub Xcode 26.6 has now built the app and
extensions at e82cae4; simulator installation exposed missing extension display names,
which were fixed. Foundation run 39560965568 at 528a9ac passes native build, simulator
onboarding, core and secret checks. Demo run 39563358861 at 17b1318 passes 85 core tests on both platforms and builds all
three native targets. Its UI step stopped during simulator system-data migration before
XCTest. Runs 39564263323 (7d5a96c) and 39564434377 (c763956) subsequently pass all
native targets, demo edit/restart/exit, English onboarding and German light/dark navigation.
See validation/github-native-demo.json. Current quantity editor changes require their own CI.

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
90 portable tests pass, including five demo isolation/restart/rollback tests and five
manual quantity normalisation, invalid-input and persistent-outbox checks. The editor
accepts fractions/ranges/decimal commas and preserves unmeasured phrases as text; its native
keyboard, validation and save lifecycle require current Apple CI validation.

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
recovery UI/device validation and reference-safe restoration beyond recipes; expanded UI tests; icon appearance validation; genuine screenshot review; expanded demo planning/editor native
acceptance; TestFlight signing/upload;
accessibility audit; full performance/privacy/security validation.

The server repository's implementation checklist tracks the full product phases. Neither
repository is declared complete, production-ready or App Store-ready. Both independent
repositories are published under CLOUDCOOKCH; no stable release has been published. The
first GitHub run passed core tests/secret scanning but stopped before native compilation
because the runner had Xcode 26.6 rather than the previously hard-coded version 27.
CI now checks actual iOS 26+ capability; the foundation native run passes as recorded
above. Current demo UI acceptance remains open.
