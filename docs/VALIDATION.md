# Native validation evidence — 2026-10-20

**9 Swift core tests pass**, compiled with Swift 6.2.1 in Linux Docker with SQLite headers.
Tests cover local restart/outbox identity, preservation of unsent drafts, tombstone rejection,
delta acknowledgement, backend identity pinning, share-inbox restart/acknowledgement,
decimal/non-numeric scaling and canonical recipe/mutation codecs.

Pinned OpenAPI SHA-256, required route/property sets, 113 English/German localisation keys,
static error lookups, Swift formatting and native-source syntax parsing pass. Source secret
scanning reports no findings. Workflow YAML and export configuration parse successfully.

SwiftUI/UIKit/VisionKit/WidgetKit/LocalAuthentication/Security/UserNotifications sources are
**not compiled against an Apple SDK** here. Syntax parsing does not establish type correctness
or a working native application. UI test sources exist but have not run. No simulator,
physical device, archive, signing, TestFlight upload or App Store submission is claimed.
No iOS screenshots have been fabricated. Genuine admin console screenshots reside in the
independent server repository and are not screenshots of this app.

The backend has 45 passing tests and a passing real-container restart/export/restore E2E.
Its container security gate still fails on 44 high package/advisory matches (8 unique
advisories), with no critical matches. Full acceptance and distribution remain blocked by
both incomplete engineering and unverified release requirements. See IMPLEMENTATION.md.
