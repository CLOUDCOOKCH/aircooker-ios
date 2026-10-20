# Native implementation status

The Swift core is compiled and tested in a Swift 6.2.1 Linux container. SwiftUI, UIKit,
VisionKit, WidgetKit, LocalAuthentication, Keychain and notifications have not been compiled
or tested with an Apple SDK here. All native UI functionality is therefore unverified.

Implemented sources: five-tab navigation, HTTPS onboarding, QR scanner, initial setup/login,
Keychain token vault, optional local access lock, persistent SQLite/outbox, server identity
pinning, sync, recipe list/detail/editor/scaling and photo selection/cache, week calendar assignment,
occurrence-aware movement/duplication, day/week copy previews, template save/apply, recurrence editing,
accessible context-menu alternatives, pantry editing, import queue/review sources, App Group
share inbox, cached widgets and notification scheduler. English/German resources are present.

Tested core: prepared photo + recipe + outbox atomic persistence, upload-before-recipe sync,
replay after lost responses/restart, photo cache, v1→v2 local migration, bounded recurrence,
exceptions, detached movement, civil dates, template validation and atomic copy batches.

Remaining: full native SDK build/Swift concurrency validation; photo quota/cleanup UI;
arbitrary copy destinations and complete leftover/recommendation interfaces; import preview lifecycle
end-to-end; provider disclosure/configuration; notification settings and rescheduling;
widget rollover/deep links and native recurrence validation; logout/server revocation and deletion UX; recoverable sync
conflict UI; UI tests; app icon; screenshots; demo environment; TestFlight signing/upload;
accessibility audit; full performance/privacy/security validation.

The server repository's implementation checklist tracks the full product phases. Neither
repository is declared complete, production-ready or App Store-ready. No remote repository
or release has been published. Intended owner: CLOUDCOOKCH.
