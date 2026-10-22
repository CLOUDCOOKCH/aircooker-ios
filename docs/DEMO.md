# Isolated offline demonstration

Choose **Explore the app** on onboarding. No server URL, household password or hosted
account is needed. The persistent demo uses `offline-demo/mealf.sqlite3`, a separate
identity and SQLite/outbox transactions. It seeds sample recipes, eight planned slots in
the initial week, cooking history, pantry staples, leftovers and a template. Changes and
deletions survive relaunch and re-entering the demo; reopening never overwrites them.

The demo supports the actual local recipe editor, serving scaling, recipe search/layout,
calendar operations, pantry, leftovers, templates and recommendation engine. It uses the
same views and storage operations as normal offline editing. It is not an alternative
server transport. Import, AI, Bring, server settings and sync/recovery controls require a
real backend and are not simulated. Notification/widget preferences are disabled so the
demo does not change a household's reminder settings or publish sample content to widgets.

A persistent main-navigation demo notice and onboarding/settings copy identify sample data and
illustrative photography. `App/Assets/DemoChicken.png` is original generated artwork used
only in the demo. Other missing images remain neutral placeholders. The source image is
prepared with the same bounded, metadata-stripping photo path used by the editor. No
sample record or photo is automatically inserted into a household database or uploaded.

**Exit demo** returns to onboarding. The real household database, server selection,
credentials, pending edits and revocation capabilities are retained. The demo never has an
API client or sync engine, and its fixed identity refuses a real-server binding. Database
seeding, photos, entity writes, outgoing mutations and its seeded marker commit together.
Mode changes invalidate older view loads and clear derived views before displaying another
database. Relaunching starts normal onboarding; enter the demo again to continue your edits.

## Verification and remaining checks

Native run 39564263323 at 7d5a96c passes demo entry, recipe creation/persistence after
restart, search/exit, English onboarding and German light/dark navigation on iPhone Air
with iOS 26.5. Genuine captures and an unsigned simulator build are in the Actions
artifacts; download them from the run page. File-service capture retrieval returned HTTP
403 in this workspace, so no visual-quality review is claimed here. Later quantity editor
changes require their own native run. See validation/github-native-demo.json.

Five portable tests prove actual seeded planning data, household-date/German content,
restart/edit/deletion/outbox preservation, failed-seed/media/identity rollback and refusal
to overwrite a household database. The full portable suite has 85 passing tests. These
checks do not validate Apple's frameworks or prove UI rendering.

Native UI tests exercise entry, recipe creation, app restart, search, demo exit and German
navigation. CI runs them on an available supported iPhone simulator, then checks German
navigation in system dark appearance. XCTest attachments are genuine running-app captures,
with sample content explicitly labelled. Their success and visual quality must be checked
before release; source code or generated illustrative concepts are not that evidence.

Still required: physical-device performance, VoiceOver/large text, accessibility contrast,
all planning/editor/leftover/template workflows, signed extensions, real backend/two-device
sync and credential-gated integrations. A useful demo does not establish release acceptance.

A successful native CI run publishes a `simulator-development-build` artifact. On a compatible Apple Silicon Mac,
unzip its `mealf-simulator.zip`, boot a compatible simulator and install with
`xcrun simctl install booted mealf.app`. This is an unsigned simulator development app,
not an iPhone installation package or TestFlight release. UI/screenshot artifacts are
published separately and should be inspected against the exact source commit.
