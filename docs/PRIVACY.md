# Privacy policy draft — not final legal text

aircooker is an independent, free, open-source application that connects to a server operated
by you or your household. It does not include mandatory analytics, advertising or tracking.
Recipes, meal plans, pantry items, leftovers and queued changes are stored on your device
and the configured self-hosted server. Device sessions permit per-device revocation.

If configured and explicitly requested for an import, source text is sent to the selected
AI endpoint for recipe extraction. Cloud providers may process that content under their own
terms; local providers can keep processing within your infrastructure. AI is optional.
Bring integration sends required ingredient names and quantities from the backend to the
selected Bring list. Bring is a separate service with its own privacy policy and account.

Backend credentials are stored in Keychain on the device. Bring credentials are encrypted
separately from household records. Neither encryption prevents a trusted server operator
or compromised device/host from accessing data. Non-secret exports contain private recipe
and planning content and should be handled accordingly.

Signing out preserves cached device content. A pending refresh capability remains in
device-only Keychain until server revocation succeeds; the app retries on launch/foreground
and manual request. Offline sign-out cannot immediately revoke a server session. Complete app/server deletion
controls, retention periods, operator contact, support URL, jurisdiction and accurate App
Privacy disclosures must be finalised before distribution. Users should not be told that
unimplemented deletion or anonymisation controls already exist.

The app's `PrivacyInfo.xcprivacy` declares no tracking and required-reason UserDefaults
access under CA92.1: settings, server selection, import identifiers and local signed-out
state are used only within this app. Authentication tokens remain in Keychain. No required
reason is used to permit cross-app tracking or advertising. The manifest is not a substitute
for App Store privacy answers: review user-configured server, AI and Bring data flows and
Apple's current reason definitions before distribution. Validate the archived privacy report
and audit any new APIs or dependencies when they are added.
