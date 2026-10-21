# Device sign-out and offline revocation

The portable implementation is tested; native Keychain, SwiftUI and notification cleanup
still need Xcode/simulator/device validation before release.

Sign-out preserves cached recipes, photos, calendar data, rejected drafts and outgoing
mutations. It removes active device authentication by atomically moving its refresh
capability into a pending queue in the same device-only Keychain record. The next launch
checks that active credentials exist before reopening the library. This is not data deletion.

Credential generations and conditional writes prevent an in-flight refresh or login from
restoring signed-out credentials. Already-sent requests may commit on the server; a refresh
response is allowed to finish and is rejected by the generation check. Late successful login
sessions are also queued for revocation. Mutation replay retains its original identifiers.
The existing legacy token-only Keychain value is upgraded in place before network use.
Unknown or corrupt credential formats fail without clearing the record.

Revocation uses the pinned server's `/api/v1/auth/revoke`, with no active Bearer token.
Only a same-origin HTTPS 204 receipt removes the pending capability. Current or rotated
refresh capabilities revoke only their own session. Retries are idempotent. Offline,
timeout, 401/404/429/500 or unexpected 200 responses keep the queue intact. Older servers
need an upgrade; the administration console can revoke devices independently.

The app retries once per pending capability on launch, foreground and explicit retry.
There is no promise of exact iOS background timing. The onboarding and settings sources
show pending server sign-out with a retry action. Keep the app installed until the server
is reachable, or revoke the session through the console. Native layout/VoiceOver, Keychain
failure and foreground/background race checks remain unverified.

Only server URL identifiers go in preferences; active/pending tokens stay in Keychain with
`AfterFirstUnlockThisDeviceOnly`. Never add them to SQLite, App Groups, shared import
files, widgets, logs or exports. `AppModel.vaultFor` reuses one actor per exact server
service so credential read/apply/write transitions remain serial even for older clients
with requests still in flight. Share Extension and widgets do not access these secrets.
