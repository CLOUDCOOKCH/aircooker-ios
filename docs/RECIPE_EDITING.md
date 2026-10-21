# Manual recipe quantities

The editor accepts decimal amounts, common Unicode/simple/mixed fractions and ordered
ranges such as `1/2–3/4` or `1–2`. Commas and points are decimal separators, never thousands
separators. Units remain separate; the app does not guess weight/volume conversions.

On save, `CookingQuantity.normalise` creates an independent recipe snapshot with canonical
decimal strings and separate lower/upper quantity fields. Nonterminating fractions round
to 12 decimal places. Existing original ingredient text is retained for numeric edits;
when it is missing, the entered amount/unit/name is kept. An explicitly typed unmeasured
phrase, such as `to taste` or `nach Geschmack`, replaces the ingredient's Original text
with that edited measure/name, clears both numeric fields and shows an inline explanation.
An empty amount preserves existing original text. No nutrition is generated.

Invalid arithmetic, reversed ranges, units in numeric inputs and amounts over one million
disable Save and show an inline correction. Servings must be one positive amount, with no
range. Native punctuation keyboards allow slash and range input. Normalisation leaves the
editing draft untouched and submits the canonical snapshot through the existing atomic
SQLite/outbox/photo save. A failed save keeps the sheet and draft available.

Five portable tests cover fraction/range arithmetic, bounds and invalid inputs, text and
metadata preservation, canonical encoding/idempotence, invalid servings/orphan bounds,
scaling and persistence of a canonical outgoing mutation across a local-store restart.
The full core suite has 90 passing tests. Apple keyboard, Dynamic Type/VoiceOver and native
editor lifecycle checks remain required; portable tests are not those platform checks.
