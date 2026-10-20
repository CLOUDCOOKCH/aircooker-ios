# Offline planning semantics

Calendar records store ISO civil dates separately from timestamps. Household time zone
converts the current instant to a civil date; Gregorian UTC arithmetic moves between civil
dates, avoiding daylight-saving shifts. The native calendar expands recurring records
locally, so viewing a week works offline. Home and widget snapshots use the same expansion.

A recurrence has an interval of 1–52 weeks, an inclusive end within ten years and at most
520 excluded dates. Queries cover at most 366 days and calculate only occurrences in that
window. No infinite database rows or iOS background timer is required.

Moving one recurring occurrence writes an exception to its master and a new independent
meal. Both changes and outbox mutations commit together locally. Removing one occurrence
adds an exception; removing the entire series writes a tombstone. The source UI provides
both drag movement and a date/category picker. Editing repetition changes the master rule
and retains existing exceptions. These native interfaces still require Apple SDK tests.

Day/week copying creates independent uncooked meals and strips recurrence. Copying a day
to tomorrow or a week to the following week displays a preview before adding records;
existing meals are preserved. Weekly templates preserve weekday/category/servings and
require referenced recipes to be available. Applying a template also requires explicit
preview approval. Copying leftovers is rejected so their portions cannot be double spent.
There are at most 100 local changes in a batch.

The local batch is atomic. The current sync engine sends its ordered mutations individually;
server/network rejection may leave a partially committed remote batch while unacknowledged
changes stay queued. This is visible as pending/error state and is not a distributed atomic
transaction. A transactional sync-batch protocol, advanced copy destinations, leftover and
recommendation interfaces and recovery UX remain work before full acceptance.
