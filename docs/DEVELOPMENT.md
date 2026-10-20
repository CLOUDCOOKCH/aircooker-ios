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

## Offline test matrix

Core tests exercise local restart with pending changes, incoming remote edits while a local
mutation is pending, server tombstone rejection preserving the draft, delta application,
backend identity changes, share-inbox durability, durable photo transfer retries, local
schema migration, recurrence/template/copy batches, per-entity rejected changes and atomic
archived recovery; see [sync recovery](SYNC_RECOVERY.md). See [planning](PLANNING.md). Backend tests exercise two sessions,
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
