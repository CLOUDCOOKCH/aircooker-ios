# Recovering rejected offline changes

Local changes and their mutation envelopes remain transactional. A server rejection is not
permission to delete the user's work. Local schema version 3 adds durable server snapshots,
per-entity failure tracking and a local recovery archive. Version 1/2 upgrades preserve
existing outbox IDs/photos and replay server deltas from cursor zero to rebuild snapshots.
Replaying old pages cannot replace a newer accepted cached entity.

## Synchronisation behaviour

The engine pushes ready mutations in order. A `rejected_tombstone` receipt or a mutation
HTTP 400/404/409/413/422 pauses that entity, including its later queued edits. Other entities
continue and server deltas are pulled. Every incoming delta updates the server snapshot;
pending local edits remain visible and cannot be replaced by it. Rejections survive restart.
Authentication failures, timeouts, connectivity errors, rate limits and server errors retain
the original ready queue for a later retry. Invalid receipt identities/statuses or malformed
delta order fail without deleting the queue or advancing its cursor.

A deleted server UUID is never resurrected. The status directs users to Settings → Sync and
saved drafts. The native screen shows the local/server version, an explanation or stable
error code, and these explicit actions:

- Retry the identical original envelope after correcting an external prerequisite. Tombstone
  rejections cannot be retried as an upsert to the same identity.
- Keep a non-deleted recipe as a new recipe with a fresh UUID.
- Accept the received server version (including deletion), retaining an archived local draft.

For a previously accepted record, accepting an unknown server state is refused until a
snapshot is available. A never-accepted local record can be archived and removed locally.
Recipe copying preserves its image reference and content; it does not silently rewrite
existing meal, leftover or template references. Those relationships require user review.
Other entity kinds can be archived/retried but do not have automatic reference-remapping
or copy recovery.

## Atomicity and stale decisions

A recovery decision archives the latest entity and **all** its queued envelopes, removes
that entity's old outgoing work, restores the pulled server version locally, and optionally
queues a fresh recipe. These changes commit together or roll back together. No server write
is performed by accepting the server version. The review includes a snapshot of entity,
queue and server state; a change to any of them invalidates the decision instead of applying
it to a newer edit the user has not reviewed.

Recovery actions use the sync coordinator, which refuses them while a network sync request
is in flight. The app also coalesces concurrent sync triggers. Direct LocalStore callers
must coordinate with SyncEngine before resolving/retrying. Ordinary offline editing remains
available and automatically invalidates an older open review.

## Saved drafts

Saved local drafts are paginated in Settings. A non-deleted archived recipe can later be
restored under another fresh UUID; the archive remains. Text sharing exports `formatVersion`
1 JSON with the entity snapshot, error code, diagnostics timestamp, original device and
mutation IDs, and queued payloads. It contains no tokens/passwords or photo files. This is a
local draft artifact, **not** the household export format and cannot be imported through the
server's household restore endpoint. Review the content before sharing it.

Archives live only in this installation's protected SQLite database, not in server backups.
Uninstalling the app removes them. No automatic archive retention/purge is enabled; future
media cleanup must retain images referenced by archived drafts.

## Verification and remaining work

Portable Swift tests cover independent sync progress after rejection; server snapshot and
latest-local preservation; multi-edit archive/copy and restart; later restore; stale local
and server review decisions; unknown server-state refusal; transaction rollback; identical
retry IDs; authentication-failure classification; receipt/page validation; migration replay;
and recovery exclusion during an in-flight request. These use explicit synthetic transports.

SwiftUI review, confirmation, sharing, pagination, navigation, Dynamic Type/VoiceOver and
interaction with backgrounding/lock still need Xcode/device validation. Photo transfer
failures can still stop a sync before mutation reconciliation. Cursor-ahead-of-server after
backup rollback needs an explicit full-resync workflow; this increment does not silently
reset or replace a household. Cross-entity dependency remapping, archive import/media bundles,
automatic retry/backoff enhancements, remote logout and deletion controls remain work.

Native validation checklist (not yet executed): reject a recipe edit from a second device;
open review, edit it again and verify stale-review feedback; accept deletion with archive;
restore a recipe copy with cached photo; inspect old calendar references; share draft JSON;
exercise archive pagination, permission/lock/logout, app termination and large Dynamic Type
with VoiceOver. A rejected recipe must not stop independent imports or meal/pantry edits.
