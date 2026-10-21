# ADR: Preserve rejected offline edits in a local recovery archive

Status: accepted for the development implementation, 2026-10-20.

Server commit order and deletion tombstones remain authoritative. A rejected mutation must
not become a permanent global outbox blockage, and accepting remote state must not erase
unsubmitted household content. An elaborate field-by-field conflict editor is out of scope.

Store latest incoming server snapshots separately from optimistic local entities. Pause a
rejected entity's outgoing queue while allowing other entities and incoming deltas to
progress. Archive the latest local snapshot and every outstanding envelope transactionally
before resolving a rejection. Recipe recovery creates a new identity; it never rewrites a
server tombstone or silently redirects calendar references. Other kinds retain explicit
retry/archive paths until reference-safe reconstruction is designed.

Recovery requires an unchanged review basis and coordinator exclusion from in-flight sync.
The schema-v3 upgrade replays retained deltas without replacing optimistic edits or regressing
newer accepted cache revisions. Archives are private to the device, retain photo references,
and can be shared as versioned text. They are not silently purged or advertised as server
backups. This adds SQLite storage and requires native lifecycle tests and future archive/media
retention design. The schema-4 extension adds explicit durable full-resync staging after a history rollback;
see SYNC_RECOVERY.md and server ADR 007. Native lifecycle checks remain required.

Rejected alternatives: dropping an invalid envelope loses edits; retrying a tombstoned UUID
cannot succeed; device-clock precedence conflicts with the accepted policy; accepting a
remote state without preserving the local queue makes recovery irreversible.
