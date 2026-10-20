# Native validation evidence — 2026-10-20

**34 Swift core tests pass**, compiled with Swift 6.2.1 in Linux Docker with SQLite headers.
Tests cover local restart/outbox identity, preservation of unsent drafts, tombstone rejection,
delta acknowledgement, backend identity pinning, share-inbox restart/acknowledgement,
decimal/non-numeric scaling and canonical recipe/mutation codecs. New tests cover atomic
photo/outbox persistence, failed-write rollback, lost upload/mutation response replay after
restart, cached photos, schema upgrades/future-schema rejection, civil dates across DST/year
boundaries, bounded recurrence/exceptions, detached moves, templates and atomic copy batches. New tests enforce leftover
reservations, decimal input validation, discard semantics, occurrence-specific cooked history,
local stale-preview rejection, selected approval/outbox restart, approval rollback and
Python/Swift equivalence across three canonical recommendation cases.

Pinned OpenAPI SHA-256, required route/property sets, 194 English/German localisation keys,
static error lookups, Swift formatting and native-source syntax parsing pass. Source secret
scanning reports no findings. Workflow YAML and export configuration parse successfully.

SwiftUI/UIKit/VisionKit/PhotosUI/ImageIO/WidgetKit/LocalAuthentication/Security/UserNotifications sources are
**not compiled against an Apple SDK** here. Syntax parsing does not establish type correctness
or a working native application. UI test sources exist but have not run. No simulator,
physical device, archive, signing, TestFlight upload or App Store submission is claimed.
The test container used an executable 2 GiB tmpfs for compiler temporary/build files after
its disk filled; test build outputs are ephemeral. No iOS screenshots have been fabricated. Genuine admin console screenshots reside in the
independent server repository and are not screenshots of this app.

The backend has 72 passing tests and a passing real-container photo upload/replay/restart, leftover exclusion, suggestion approval/replay and JSON/ZIP restore E2E.
Its container security gate still fails on 44 high package/advisory matches (8 unique
advisories), with no critical matches. Full acceptance and distribution remain blocked by
both incomplete engineering and unverified release requirements. See IMPLEMENTATION.md.
