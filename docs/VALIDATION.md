# Native validation evidence — 2026-10-20

**53 Swift core tests pass**, compiled with Swift 6.2.1 in Linux Docker with SQLite headers.
Tests cover local restart/outbox identity, preservation of unsent drafts, tombstone rejection,
delta acknowledgement, backend identity pinning, share-inbox restart/acknowledgement,
decimal/non-numeric scaling and canonical recipe/mutation codecs. New tests cover atomic
photo/outbox persistence, failed-write rollback, lost upload/mutation response replay after
restart, cached photos, schema upgrades/future-schema rejection, civil dates across DST/year
boundaries, bounded recurrence/exceptions, detached moves, templates and atomic copy batches. New tests enforce leftover
reservations, decimal input validation, discard semantics, occurrence-specific cooked history,
local stale-preview rejection, selected approval/outbox restart, approval rollback and
Python/Swift equivalence across three canonical recommendation cases. Presentation tests cover
strict route parsing, household date boundaries, spring gaps/autumn repeated hours, cooked
meal suppression, chronological reminder limits, meal grouping, widget recurrence/rollover,
expiry, name privacy and malformed-cache bounds. Recovery tests cover per-entity rejection
isolation, independent sync progress, pulled tombstones/server snapshots, multi-edit archive
and fresh recipe copies, restart/later restore, stale local/server reviews, unknown server
state, rollback on write failure, identical retries, auth failures, invalid receipts/deltas,
active-request exclusion and schema-v3 replay without cached-state regression.

Pinned OpenAPI SHA-256, required route/property sets, 240 English/German localisation keys,
static error lookups, Swift formatting and native-source syntax parsing pass. Source secret
scanning reports no findings. Workflow YAML and export configuration parse successfully.

SwiftUI/UIKit/VisionKit/PhotosUI/ImageIO/WidgetKit/LocalAuthentication/Security/UserNotifications sources are
**not compiled against an Apple SDK** here. Syntax parsing does not establish type correctness
or a working native application. UI test sources exist but have not run. No simulator,
physical device, archive, signing, TestFlight upload or App Store submission is claimed.
The test container used an executable 2 GiB tmpfs for compiler temporary/build files after
its disk filled; test build outputs and compiler caches are redirected to the tmpfs and are ephemeral. No iOS screenshots have been fabricated. Genuine admin console screenshots reside in the
independent server repository and are not screenshots of this app.

The backend has 81 passing tests and a passing real-container photo upload/replay/restart, leftover exclusion, suggestion approval/replay and JSON/ZIP restore E2E.
Its Chromium administration workflow passes with explicit AI/Bring test doubles, and
encrypted AI settings persist across container restart without entering exports.
Its container security gate still fails on 44 high package/advisory matches (8 unique
advisories), with no critical matches. Full acceptance and distribution remain blocked by
both incomplete engineering and unverified release requirements. See IMPLEMENTATION.md.
