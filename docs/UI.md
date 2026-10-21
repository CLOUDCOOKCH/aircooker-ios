# Native presentation

Keep the five native tabs, NavigationStack pushes, system sheets, grouped settings and
native controls. Home gives the selected day's meals the first content position and keeps import /
creation in the toolbar. The default selected day is today in the household time zone. Recipes are real library objects in an adaptive grid; no sample
recipes or stock food photographs are inserted into a household library.

`KitchenStyle.swift` owns semantic grouped backgrounds, surfaces, photo placeholders,
16-point recipe/meal corners and SF Symbols for meal categories. `AccentColor` has light
and dark variants; the root binds it explicitly. Body and controls use system Dynamic Type
styles throughout, including headings. Missing photos remain
neutral placeholders. Photos fill a stable clipped frame using bounded cached data.

Separate an empty library from empty search results. Preserve recipe editing/scaling,
calendar context-menu alternatives, sync errors, local drafts and existing navigation.
Do not fill presentation gaps with fabricated Bring status or invented recipe metadata.
The Home shortcut to settings remains available through the tab bar; integration setup
and status belong in the actual administration console until a typed native integration
status flow is implemented.

Validation: portable tests, formatter, syntax parser, contract/localisation scripts. Native
Apple build, iPhone/iPad rendering, large Dynamic Type, VoiceOver, dark/high-contrast modes,
keyboard/touch interaction and image memory/performance checks remain required. There are
no genuine iOS screenshots yet; the web console captures are not evidence for this app.


Home now has a Monday–Sunday selector, previous/next-week actions, a focused meal image,
quiet empty meal slots and a real weekly planning count. `PlannerOverview` expands local
recurrence rules and counts occupied breakfast/lunch/dinner slots rather than dishes.
Selected civil dates remain separate from absolute timestamps. Foreground date state
refreshes periodically and on scene activation; this does not schedule background jobs.

`MealAssignmentView` is shared by Home and Calendar: searchable recipes with thumbnails,
leftover navigation, an explicit saving state and the existing transactional offline save.
Settings keeps native grouped rows, independent recovery access and secure browser access
to the backend administration console. It contains no fabricated connection status.

The phone layout stacks planning and library content; regular widths use a primary meal
column and a secondary planning/library column. Accessibility text sizes retain a single
column and scrollable date controls. These are implemented sources, not a claim of tested
Apple layouts. The accompanying illustrative visual concept is separate from app captures;
no generated meal photograph or sample recipe is inserted into the live library.

The weekly summary is now one calendar navigation target, with the selected week's real
slot count and a subdued progress indicator. Its heading uses “This week” only when the
selected week contains today. Count transitions respect Reduce Motion; suggestion approval
and leftover navigation remain separate actions.

Recipes offers a native layout menu for photo cards or a compact list. The choice is a
device-local UserDefaults preference and survives relaunch; both presentations use the same
search results and recipe destinations. Shared list rows show actual ingredient counts and
optional ratings, with vertical metadata fallback when horizontal space is insufficient.
The layout choice, long German labels, large text, screen-reader output, Reduce Motion and
light/dark rendering still need simulator/device verification. No native capture is claimed.

Navigation and controls use SwiftUI's native Liquid Glass APIs on the existing iOS 26+
target. The standard TabView and toolbar retain system rendering. The tab bar can minimise
on downward scrolling; Reduce Motion or accessibility text sizes keep it expanded.
Create actions use `glassProminent`, and the suggestion action uses `glass`.

The week selector, week navigation, calendar shortcut, over-photo meal label and sync
notices share `kitchenGlass`, which uses regular system glass. Reduce Transparency or
increased contrast substitutes an opaque semantic surface for these custom glass regions.
Selected dates retain a solid accent and a contrasting foreground. Recipe text, ingredients,
settings and planning summaries keep readable semantic content surfaces. Missing photos
retain a normal category label without requiring an image backdrop. No shader, fake blur
texture, custom tab bar or third-party glass dependency was introduced.

These are source changes, not verified iOS 27 captures. Apple SDK compilation, material
contrast over different photographs, light/dark appearances, all accessibility combinations,
tab-bar minimisation/restoration, toolbar grouping and touch/scroll behaviour remain gates.


The explicitly entered offline demo uses the same views with a separate database, no API
client/sync engine and a persistent sample-data indicator. Household data is cleared from
derived views before changing modes, without deleting stored content. Sample food artwork
is original and illustrative; it never populates a real household library. Server features
show a clear limitation instead of a fake working integration. Import review warnings now
live within the editor's scrolling form and are translated into English/German. Native
Demo UI captures and their visual review are pending; see DEMO.md.
