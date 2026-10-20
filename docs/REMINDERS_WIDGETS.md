# Reminders, cached widgets and navigation

The portable planner is tested in Swift on Linux. UserNotifications, WidgetKit, SwiftUI,
App Group embedding and system delivery have not been built or exercised with an Apple
SDK here. The following describes implemented sources and remaining device checks.

## Local reminders

Settings → Reminders and widgets exposes a master toggle, separate breakfast/lunch/dinner
switches and clock times. Enabling requests notification permission explicitly. Launch,
sync and ordinary calendar edits never request permission. Denied permission provides a
link to the application's system settings. Preferences persist locally on the device.

The planner expands 28 days of cached meals, skips meals marked cooked and groups a date's
meal category into one reminder. It keeps the earliest 50 future reminders, leaving room
under iOS's request limit. Times use the household IANA time zone, not the current travel
location. A nonexistent spring clock time advances to the next real time; a repeated autumn
hour uses its first occurrence. UTC calendar-trigger components preserve the computed instant.

After a successful local reload, plan edit, sync or settings change, native reconciliation
updates changed requests and removes obsolete requests in the `aircooker.meal.` namespace.
Other notification IDs are preserved. Reentrant scheduling coalesces toward the latest
requested plan. OS failures surface as errors rather than a claimed successful schedule.
No APNs account, external push service or exact background execution is assumed. Opening
the app replenishes the finite upcoming reminder horizon.

Recipe names are off in notification bodies by default. Enabling names explicitly allows
them on the Lock Screen. Taps route to the relevant recipe or day; grouped meals open the
day's calendar. Notification delivery, permission handling and foreground presentation
still require simulator/physical-device validation.

## Offline widgets

The main app writes a protected, atomic `meals-widget-v1.json` App Group snapshot containing
14 civil dates, recurrence-expanded meals, category/order and navigation UUIDs. It stores
at most three visible recipes per category and a remaining count; no credentials or images
are copied. A bounded decoder checks format version, dates, categories, sizes and counts.
The old single-day `today.json` cache is removed after successful publication.

The widget creates timeline entries at household midnight, including DST changes, plus an
expiry entry. Tomorrow's cached meals can appear while the main app stays closed. After
the cached horizon, it asks the user to open the app rather than showing an old day's meals.
iOS controls actual refresh and rendering; no precise background refresh is promised.

Small widgets show all three meal categories and open that day. Medium/large widgets offer
per-meal links; large widgets show more entries. Widget name visibility is configurable
separately from app authentication. When names are hidden, the snapshot omits recipe names.
WidgetKit may retain an earlier rendered view until it refreshes; Face ID does not hide
widgets automatically. Signing out cancels meal reminders and clears derived widget files
while preserving the local database and pending edits. The signed-out state persists across
restart; remote session revocation and fuller account/data deletion remain incomplete.

## Deep links

Supported read-only routes:

- `aircooker://recipe/<UUID>`
- `aircooker://meal/<UUID>?date=YYYY-MM-DD`
- `aircooker://calendar?date=YYYY-MM-DD`

Parsing rejects credentials, fragments, extra/duplicate query parameters, malformed UUIDs
and invalid dates. Routes never configure servers or carry passwords. A link received while
locked or signed out remains pending until local access/authentication is restored. Missing
or moved meals offer the relevant calendar day instead of opening an unrelated record.
Calendar links navigate to the target week and scroll toward the target date.

## Required Apple validation

Build every target with production Xcode, then verify permission grant/denial/revocation,
changes while offline, removal/replacement of pending requests, actual DST delivery, title
privacy, foreground taps, locked/signed-out cold launches, multiple dishes per meal, widget
midnight rollover/expiry, locale and Dynamic Type sizes, and logout after interrupted cleanup.
Core test success and syntax parsing do not establish any of these platform outcomes.
