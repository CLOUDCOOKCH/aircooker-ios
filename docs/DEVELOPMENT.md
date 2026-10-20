# Development and verification

`Sources/AirCookerCore` contains wire models, HTTPS API client, SQLite local store, durable
mutation queue, sync coordinator and file-backed share inbox. App sources use an observable
main-actor model and SwiftUI. Shared content and widgets use an App Group; no credential is
placed in the App Group or a QR code. File protection is applied to the app data directory.

## App Group and extensions

Use the same `AIRCOOKER_APP_GROUP` setting on every target. Share Extension validates public
HTTPS URL structure/text size and atomically writes a unique import envelope before it
completes. The main app acknowledges the file only after backend acceptance and retains the
job ID before removing the file. Duplicate submissions use the same request ID. Progress
and editable previews live in the main app; automatic background transfer is not promised.

Widgets read a local `today.json` snapshot and work without network access. They display
the snapshot date to make stale cached content visible. Timeline refresh requests are
best-effort. Small/medium/large sources exist, but extension embedding, real refresh timing,
recurring-meal snapshots and deep-link handling still require validation/implementation.

Local notification scheduling code uses UserNotifications with a bounded request count;
it is not fully connected to preferences/rescheduling yet. The app must not request
notification permission until the user enables reminders. APNs is not required.

## Localisation and accessibility

Resources use `en.lproj` and `de.lproj` with matching keys. Add new strings to both and keep
translation parity checks passing. Preserve the imported recipe language. Use system fonts,
native controls and semantic colours. Test large Dynamic Type, VoiceOver, contrast, keyboard
navigation and reduced motion on simulator/device; source-level design is not an accessibility
audit. Date-only fields use the household time zone, never a floating device UTC conversion.

## Offline test matrix

Core tests exercise local restart with pending changes, incoming remote edits while a local
mutation is pending, server tombstone rejection preserving the draft, delta application,
backend identity changes and share-inbox durability. Backend tests exercise two sessions,
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
