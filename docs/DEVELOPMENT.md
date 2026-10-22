# Development and verification

`Sources/MealfCore` contains wire models, HTTPS API client, SQLite local store, durable
mutation queue, sync coordinator and file-backed share inbox. App sources use an observable
main-actor model and SwiftUI. Shared content and widgets use an App Group; no credential is
placed in the App Group or a QR code. File protection is applied to the app data directory.

## App Group and extensions

Use the same `MEALF_APP_GROUP` setting on every target. Share Extension validates public
HTTPS URL structure/text size and atomically writes a unique import envelope before it
completes. The main app acknowledges the file only after backend acceptance and retains the
job ID before removing the file. Duplicate submissions use the same request ID. Progress
and editable previews live in the main app; automatic background transfer is not promised.

Widgets read a protected 14-day `meals-widget-v1.json` snapshot with household-date timeline
entries and expiry. Per-meal/day links use strict read-only app routes and defer navigation
while locked or signed out. Notification preferences are opt-in; reload/edit/sync reschedules
bounded local reminders without requesting permission automatically. See
[reminders, widgets and required device checks](REMINDERS_WIDGETS.md).

## Localisation and accessibility

Resources use `en.lproj` and `de.lproj` with matching keys. Add new strings to both and keep
translation parity checks passing. Preserve the imported recipe language. Use system fonts,
native controls and semantic colours. Test large Dynamic Type, VoiceOver, contrast, keyboard
navigation and reduced motion on simulator/device; source-level design is not an accessibility
audit. Date-only fields use the household time zone, never a floating device UTC conversion.

## Original icon and privacy manifest

`Design/AppIconSource.png` is original generated artwork, not a screenshot or third-party
brand asset. XcodeGen's pre-generation command uses Apple's `sips` to package that opaque
square source at the required 1024-pixel size before project/asset discovery. The generated
catalog PNG is ignored; no image editor, network request or package dependency is needed
for this step. Keep the source opaque and square and regenerate the project after replacing
it. Generating before the build avoids an app/extension resource dependency cycle. Inspect small-size,
dark and tinted Home Screen appearances on real Apple tooling before release.

`App/PrivacyInfo.xcprivacy` declares the required-reason use of local UserDefaults and no
tracking. Review the archive privacy report and current Apple policy before distribution;
the manifest does not finalise the App Store privacy questionnaire.

## Offline test matrix

Core tests exercise local restart with pending changes, incoming remote edits while a local
mutation is pending, server tombstone rejection preserving the draft, delta application,
backend identity changes, share-inbox durability, durable photo transfer retries, local
schema migration, recurrence/template/copy batches, per-entity rejected changes and atomic
archived recovery, durable history-proof checkpoints and staged full rebuild after server
restore; see [sync recovery](SYNC_RECOVERY.md). See [planning](PLANNING.md). Backend tests exercise two sessions,
server-order conflicts, duplicate mutations, transaction rollback and migration restarts.
A real two-device offline/reconnect scenario, authentication expiry during sync, application
termination during submission and constrained network performance still require end-to-end
validation.

## Contract updates

`Contracts/openapi-v1.json` is a vendored, pinned server artifact; its checksum and source
version are recorded in `Contracts/pin.json`. CI checks the pin, required API paths and
schema fields. Codec fixtures are decoded and round-tripped by Swift tests. Updating the
contract requires review of both API drift and native Codable changes; a checksum alone
does not establish semantic compatibility.
