# aircooker for iOS

Native SwiftUI companion to the independently self-hosted aircooker-server.
Apache-2.0. No hosted account, payment flow, mandatory analytics or advertising SDK.

**Development sources; not a TestFlight-ready application.** The platform-independent Swift
core compiles and is tested on Linux. Native SwiftUI, Share Extension, WidgetKit, Keychain,
Face ID/device authentication, camera and notifications need macOS/Xcode validation.

## Build

The project targets iOS 26 and later (current/preceding major generation at research time).
Use a production Xcode toolchain with an iOS 26+ SDK on supported macOS. CI records the
selected toolchain and uses the latest available supported iPhone runtime; its first runner
provided Xcode 26.6. Verify Apple's current requirements before releasing. No signing
certificate or developer account is embedded.

The repository uses a local Swift package for the core and an XcodeGen specification for
app/extension targets. Install the pinned generator using Mint, then generate locally:

```sh
mint run yonaskolb/XcodeGen@2.44.1 xcodegen generate
open aircooker.xcodeproj
```

Choose your development team, unique bundle IDs and a matching App Group for app, Share
Extension and WidgetKit. Run the `aircooker` scheme on an iOS 26+ simulator. Generated project
files are ignored; the reviewed project definition is `project.yml`. There are no external
Swift runtime package dependencies. XcodeGen/Mint are development tools only.

## Core tests without Xcode

On macOS, `swift test`. On Linux with Docker:

```sh
docker build -f scripts/Dockerfile.swift-tests -t aircooker-swift-tests .
docker run --rm -v "$PWD:/work" -w /work aircooker-swift-tests
```

These tests validate SQLite persistence, outbox restart survival, pending-edit protection,
tombstone rejection, backend identity pinning, decimal scaling, durable photos, recurrence/template/copy operations and the share inbox.
They do not validate Apple frameworks or demonstrate a working iOS installation.

## Using the app sources

The app has Home, Calendar, Recipes, Pantry and Settings navigation. Enter a valid HTTPS
origin, or scan a QR containing only that origin, then authenticate with the household
account. New-server setup uses the one-time container administrator token. URLSession never
disables TLS validation. The server API-major/sync-protocol must match 1/1.

Local edits, prepared photos and outgoing mutations commit together in SQLite. Photo uploads
are acknowledged before a referring recipe is submitted; cached photos remain available offline.
The editor uses the system photo picker and strips metadata with ImageIO before saving.
These native photo APIs still require Apple SDK/device validation.

Local edits and outgoing mutations commit together in SQLite. Server-ordered changes win;
unsent local drafts are never replaced by incoming deltas. Rejected changes pause per record and remain recoverable through the saved-draft review
sources. Recipe recovery uses a fresh identity; see [sync recovery](docs/SYNC_RECOVERY.md).
Commit proofs detect restored/divergent server history. Explicit full recovery stages a
server snapshot and archives local content atomically; it never replays old edits automatically.
The core behaviour is tested; its native interface requires Apple SDK validation.
Offline imports are stored in the shared inbox and submitted when the main app can sync.
No exact iOS background execution is assumed.

The calendar sources include recurring occurrences, single-occurrence movement/removal,
day/week copy previews, weekly templates, leftover tracking/assignment and local weekly
suggestions with explicit review. See [planning semantics](docs/PLANNING.md).

Settings include per-category local meal reminders and widget-name privacy. Widgets consume
a 14-day offline cache and links open a meal or its calendar date. Notification delivery,
widget rendering and routing still need Apple SDK/device validation; see
[behaviour and checks](docs/REMINDERS_WIDGETS.md).

Settings allow a Home/Calendar/Recipes start screen and optional local device authentication.
Authentication includes Face ID where available with system passcode fallback; it does not
replace backend login. Tokens are in Keychain. Signing out preserves local data and pending
changes, and currently needs fuller revocation/data-deletion UX.

See [development](docs/DEVELOPMENT.md), [release gates](docs/RELEASE.md),
[privacy draft](docs/PRIVACY.md), [status](docs/IMPLEMENTATION.md) and the pinned
[API contract](Contracts/openapi-v1.json).

Device sign-out preserves drafts and queues offline server revocation securely. See
[sign-out behaviour and validation limits](docs/SESSION_SIGNOUT.md).

See [native presentation](docs/UI.md) for the current UI structure and Apple validation still required.
