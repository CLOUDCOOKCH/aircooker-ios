# Native validation evidence — 2026-10-21

**66 Swift core tests pass**, compiled with Swift 6.2.1 on Linux with SQLite headers.
An earlier 65-test run passed in Docker. The final run used hash-verified compiler files
from the same pinned Swift OCI image on the Debian host, with verified SQLite headers,
after VFS container allocation exhausted Docker storage. No Apple SDK was involved.
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

Pinned OpenAPI SHA-256, required route/property sets, 251 English/German localisation keys,
static error lookups, Swift formatting and native-source syntax parsing pass. Source secret
scanning reports no findings. Workflow YAML and export configuration parse successfully.

SwiftUI/UIKit/VisionKit/PhotosUI/ImageIO/WidgetKit/LocalAuthentication/Security/UserNotifications sources are
**not compiled against an Apple SDK** here. Syntax parsing does not establish type correctness
or a working native application. UI test sources exist but have not run. No simulator,
physical device, archive, signing, TestFlight upload or App Store submission is claimed.
The test container used an executable 2 GiB tmpfs for compiler temporary/build files after
its disk filled; test build outputs and compiler caches were ephemeral. Final host compiler/test caches
are isolated under the session temporary directory. No iOS screenshots have been fabricated. Genuine admin console screenshots reside in the
independent server repository and are not screenshots of this app.

The backend has 92 passing tests and a passing real-container photo upload/replay/restart, leftover exclusion, suggestion approval/replay and JSON/ZIP restore E2E.
Its Chromium administration workflow passes with explicit AI/Bring test doubles, and
encrypted AI settings persist across container restart without entering exports.
Its container security gate still fails on 44 high package/advisory matches (8 unique
advisories), with no critical matches. Full acceptance and distribution remain blocked by
both incomplete engineering and unverified release requirements. See IMPLEMENTATION.md.

Full-resync tests additionally cover same-revision divergence, head rollback, receipt proofs
before delta pull, request-time history guard failures, interrupted snapshot staging/restart
with later offline edits, another restore during staging, archived acknowledged records and
queued deletions, failed final replacement, malformed pages/payloads, the schema-3 missing-proof
upgrade, cached-photo requeue and copied import attribution. Both languages validate the
shared `sync-history-v1.json` fixture. Native recovery confirmation/reauthentication, large
libraries, physical two-device timing and Apple API type checking remain unverified.

Latest changed-file map:

- Core: `APIClient.swift`, `LocalStore.swift`, `Models.swift`, new `SyncHistory.swift`.
- Native controls: `AppModel.swift`, `SyncRecoveryView.swift`, EN/DE resources.
- Evidence: new `FullResyncTests.swift`, shared history fixture, updated existing transports,
  reviewed contract/pin and compatibility checks; README/changelog/recovery/validation docs.

Recipe-copy coverage also verifies that a full 50-entry attribution dictionary remains
within server limits without discarding the user's original metadata.
