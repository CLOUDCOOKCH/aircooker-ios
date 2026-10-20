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

## Leftovers

`portions` is the total batch size. Every active meal referring to its UUID reserves its
servings, including past cooked entries. The editor asks for unplanned portions and adds
the current reservation total within one local transaction. A zero unplanned amount is
valid when reservations remain. Decreasing total portions below bookings, changing the
booked recipe or moving preparation after a booked meal is rejected locally and by the
server. Moving/reducing an existing booking releases its old allocation before checking.

Discarding removes the unplanned availability; already reserved calendar entries remain.
Existing bookings can still be marked cooked or moved without increasing their portions.
New bookings against discarded batches fail. Deleting a batch with bookings fails; use
Discard for remaining portions instead. Existing leftovers never add recipe ingredients
to the shopping projection again.

Recording leftovers from a recurring meal detaches that occurrence and marks only that
meal cooked. The series exception, cooked record, leftover and outgoing mutations commit
together locally. Pending records survive restart. No freshness, expiry or nutritional
values are invented; the preparation date is shown when choosing leftovers.

## Local weekly recommendations

The local engine considers ratings, explicitly marked cooked history, recent calendar
history (including accepted suggestions), current-week occurrences and unallocated
leftovers. A stable seed breaks ties; regeneration can vary equally suitable choices.
Only empty selected categories are considered. Each recipe appears once by default;
users can allow repeats and override portions. Leftovers may reuse a recipe already planned
because they represent prepared portions. No AI service, network or credentials are needed.

Generation is read-only. The user selects proposed meals and explicitly adds them. Approval
compares the current recipe/meal/leftover snapshot with the preview inside the local write
transaction. A stale preview is rejected without changing existing records or losing edits.
The complete selection and outbox commit together. Device preferences are local; shared
household recommendation preferences and acceptance-specific learning remain incomplete.

Python and Swift execute the same versioned canonical fixture, pinned with the API contract.
The server separately offers a live `/suggestions/apply` transaction with durable replay
receipts and server snapshot checks. iOS uses its offline outbox, so its approval is locally
atomic and remote submission still uses individual ordered mutations. Concurrent offline
approvals on different devices may add multiple dishes to a slot; they do not overwrite
existing entries. Cross-device plan collision UX and distributed batch approval remain work.
