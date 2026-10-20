# Native implementation status

The Swift core is compiled and tested in a Swift 6.2.1 Linux container. SwiftUI, UIKit,
VisionKit, WidgetKit, LocalAuthentication, Keychain and notifications have not been compiled
or tested with an Apple SDK here. All native UI functionality is therefore unverified.

Implemented sources: five-tab navigation, HTTPS onboarding, QR scanner, initial setup/login,
Keychain token vault, optional local access lock, persistent SQLite/outbox, server identity
pinning, sync, recipe list/detail/editor/scaling, week calendar assignment/movement/duplication,
accessible context-menu alternatives, pantry editing, import queue/review sources, App Group
share inbox, cached widgets and notification scheduler. English/German resources are present.

Remaining: full native SDK build/Swift concurrency validation; photo/media offline queue;
complete template/copy/recurrence/leftover/recommendation interfaces; import preview lifecycle
end-to-end; provider disclosure/configuration; notification settings and rescheduling;
widget date/recurrence/deep links; logout/server revocation and deletion UX; recoverable sync
conflict UI; UI tests; app icon; screenshots; demo environment; TestFlight signing/upload;
accessibility audit; full performance/privacy/security validation.

The server repository's implementation checklist tracks the full product phases. Neither
repository is declared complete, production-ready or App Store-ready. No remote repository
or release has been published. Intended owner: CLOUDCOOKCH.
