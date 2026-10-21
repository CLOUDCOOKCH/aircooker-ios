# Native validation evidence — 2026-10-21

**80 Swift core tests pass**, compiled with Swift 6.2.1 on Linux with SQLite headers.
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

Pinned OpenAPI SHA-256, required route/property sets, 262 English/German localisation keys,
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

The backend has 97 passing tests and a passing real-container photo upload/replay/restart, leftover exclusion, suggestion approval/replay and JSON/ZIP restore E2E.
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


Device sign-out verification adds portable credential-envelope upgrade/future-format
rejection, offline queue restart, unchanged SQLite recipe/mutation identities, refresh and
late-login races, failed simulated secure-storage writes, malformed/unconfirmed HTTP
receipts and response-origin checks. The final total is 76 passing Swift tests. Ordinary
refresh still rotates and retries with the new access token. These tests use synthetic
URLSession responses and an encoded in-memory vault; they do not test Apple's Keychain.

The native source changes cover `AirCookerApp.swift`, `AppModel.swift`, `KeychainVault.swift`,
`RootView.swift` and EN/DE resources. Core changes are `CredentialState.swift`, `APIClient.swift`
and `Recommendations.swift`; tests are `SessionTests.swift` and
`LeftoverRecommendationTests.swift`. Contract checks/pin, README, changelog, implementation,
privacy and sign-out documentation were updated. Formatting, native syntax parsing,
273-key localisation parity and source secret scanning pass. Native build/rendering,
Face ID, lock/logout notification/widget lifecycle and physical offline devices remain
unverified. The server's current verification record is `docs/validation/session-signout.json`.


## Interface refinement

Home now leads with today's meals, planning actions and actual cached recipe content.
Recipes use an adaptive photo-led grid, separate empty-library/search states and native
create/import actions. Shared semantic surfaces, an adaptive AccentColor asset and display
text styles replace scattered green decorations. Calendar week arrows and meal actions
have explicit targets/styles; date headers distinguish weekdays and today. Photo views
keep their frame and avoid blanking an unchanged cached photo during a reload.

Changed files: `RootView.swift`, `RecipesView.swift`, `CalendarView.swift`,
`RecipePhotoView.swift`, new `KitchenStyle.swift`, AccentColor catalog, English/German
resources, README/changelog/status/this report and `UI.md`. The existing 76 portable core
tests pass, as do formatting, native syntax parsing, contract checks and 273-key
localisation parity. These checks do not compile SwiftUI or validate rendering. No native
screenshot, simulator, Dynamic Type/device or Apple accessibility result is claimed.
The independent web console has genuine Chromium captures and browser workflow evidence.


## Interactive Home planning

The current 80-test portable suite includes four new overview tests: household date/week
boundaries, duplicate-dish slot counting and leftover inclusion, recurrence exceptions and
year rollover, and rejection of invalid date/time-zone input. Existing mutation, media,
recovery, archive and offline replay tests still pass. Formatter, native syntax parsing,
contract pin and 273-key English/German parity checks pass. The API pin is unchanged.

Changed sources: new `HomeView.swift`, `SettingsView.swift`, `PlannerComponents.swift`,
`PlannerOverview.swift` and its tests; extracted views in `RootView.swift`, shared picker
in `CalendarView.swift`, typography/photo proportions in `RecipesView.swift` and
`KitchenStyle.swift`, localisations and implementation/presentation/changelog documentation.
The picker continues to use `AppModel.save` and its SQLite/outbox transaction.

No Apple SDK build or iOS screenshot was produced. The visual concept shown in conversation
is labelled illustrative and is not evidence of native rendering or actual household
content. Reference images were not successfully exposed by the connected image reader;
no pixel-level comparison to those references or motion inference is claimed. The native
layout, sheet dismiss/save lifecycle, VoiceOver, physical touch, dark appearance and large
Dynamic Type remain unverified on Apple hardware. No backend code was changed in this pass.

## Recipe layout and weekly summary

The 80 existing portable Swift tests pass after the interface-only changes. Swift format
and native source syntax parsing pass, along with the unchanged OpenAPI pin, 277-key
English/German parity and whitespace checks. No new core business logic or API was added;
these results do not test SwiftUI layout, UserDefaults persistence or animation.

Changed files: `HomeView.swift`, `PlannerComponents.swift`, `RecipesView.swift`, English/German
resources and implementation/presentation/changelog/validation documentation. Compact
recipe rows reuse the existing photo cache and detail navigation. Both library layouts
share the existing search and data source. Calendar navigation still receives the selected
civil date. No backend files were changed.

Reference images were accessible through the design connector in this pass, and a generated
design brief was read. This improves reference evidence but supplies no native build or
rendering evidence. On Apple tooling, verify layout switching with search active and after
relaunch, empty/missing-photo/unrated/long-title recipes, German and accessibility text sizes,
calendar navigation from earlier/later weeks, VoiceOver, Reduce Motion and both appearances.
No native screenshot, Apple SDK build or device result is claimed.

## Liquid Glass presentation

The current interface pass changes `KitchenStyle.swift`, `PlannerComponents.swift`,
`HomeView.swift`, `RootView.swift` and `RecipesView.swift`, plus presentation, implementation,
release, changelog and validation documentation. It uses native SwiftUI glass effects and
button styles on the existing iOS 26+ target, without changing the API or local persistence.

All 80 portable core tests pass. Formatting, native syntax parsing, contract pin validation,
277-key English/German parity and whitespace checks pass. Linux parsing does not resolve
SwiftUI API signatures, prove Apple SDK compatibility or verify system glass rendering.
No iOS 27 SDK/device execution or native screenshot was produced. The revised visual
concept is illustrative and its sample recipes are not inserted into household data.

Apple validation must exercise all five tabs, scroll minimisation/restoration, sheet and
keyboard transitions, sync notice wrapping, photo overlays and missing images, and both
appearances with Reduce Transparency, increased contrast, Reduce Motion and Dynamic Type.
Custom glass regions have explicit opaque fallbacks; system tab/tool/button accessibility
adaptation and contrast still need real-device verification.


## Native build progress and isolated demo

The GitHub runner supplies production Xcode 26.6 with a supported iOS SDK. After correcting
Section initializers and icon packaging, the app, Share Extension and Widget Extension
build successfully at e82cae4. The first simulator test could not install the app because
extension display names were missing; 528a9ac supplies them. This is compile evidence,
not a claim that UI workflows or physical-device behaviour have passed.

The demo adds five portable tests; all 85 pass on the verified Swift 6.2.1 Linux toolchain.
They cover actual seed planning/German/household-date data, stable restart/edit/deletion
queues, rejection of a household store, and rollback of entities/photos/identity. Native
mode changes clear derived snapshots, disable server client construction and restore the
original store without deleting it. These Apple-source lifecycle paths require native UI
validation. Formatting, source syntax parsing, unchanged API pin and 288-key EN/DE parity
pass. UI tests and genuine light/dark screenshot export are configured; results are pending.


Foundation GitHub run 39560965568 at 528a9ac is now green: app and both extensions build,
the onboarding UI test launches the app successfully on an iPhone simulator and keeps a
genuine capture. See validation/github-native-foundation.json for exact job IDs. Current
demo edits postdate that verified run and still require their own native acceptance.

Demo run 39563358861 at 17b1318 passes all 85 core tests on Linux and macOS,
formatting, contract/localisation and secret checks, and builds all three native targets.
Its UI step never reached XCTest: first-boot CoreLocation system-data migration exceeded
the original 180-second readiness limit. The runner now allows a bounded ten-minute boot
with progress messages and still fails if readiness is not reached. This is infrastructure
handling, not UI acceptance; no demo capture or passing workflow is claimed from that run.
