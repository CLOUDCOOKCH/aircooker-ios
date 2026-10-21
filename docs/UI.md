# Native presentation

Keep the five native tabs, NavigationStack pushes, system sheets, grouped settings and
native controls. Home gives today's meals the first content position and keeps import /
creation in the toolbar. Recipes are real library objects in an adaptive grid; no sample
recipes or stock food photographs are inserted into a household library.

`KitchenStyle.swift` owns semantic grouped backgrounds, surfaces, photo placeholders,
16-point recipe/meal corners and SF Symbols for meal categories. `AccentColor` has light
and dark variants; the root binds it explicitly. Body and controls use system Dynamic Type
styles; serif display text is limited to welcome/detail moments. Missing photos remain
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
