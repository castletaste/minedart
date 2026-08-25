---
name: minedart-world-storage
description: "Implement or debug Minedart persistence: MDRT codecs/migrations, WorldRepository, native files, IndexedDB, autosave, import/export, and compatibility tests."
---

# Minedart World Storage

Durable state is canonical in `app/lib/data/worlds/**` plus `repository_autosaver.dart`; all callers use `WorldRepository`, never direct IO/IndexedDB.

- MDRT2 is magic + little-endian metadata length + UTF-8 JSON + gzip canonical `Uint16` blocks. Decode strictly and preserve world/chunk/local ordering and `WorldDocument` defensive copies.
- Assigned IDs 1–33 and MDRT1 reading are contracts; never reuse those IDs. ID 33 is the approved additive obsidian extension. MDRT1 migrates in memory; `save/world_saver.dart` is legacy-import only.
- Preserve raw 4-bit metadata values 0–15 exactly through MDRT2, including current Alpha liquid falling/level states. Adding a block id requires registry/fixture/import review; format, dimensions, ordering, raw layout, or encoding-semantics changes require a new version and migration design.
- Native writes use a flushed temp file then rename under Application Support with filename-safe ids. Web uses awaited IndexedDB transactions in `minedart/worlds` and surfaces open/request failures.
- Storage key must equal metadata id. Duplicate/import collisions fail; native and Web import/export the same MDRT bytes.
- Autosaves stay serialized/coalesced; feed repository metadata changes through `replaceMetadata`. Before switching/resetting/deleting the current world, stop and await in-flight save; destructive UI confirms.
- Listing may skip one corrupt record, but explicit load must surface corruption rather than replace user data.

Test codec failures/migration, assigned-id and metadata round-trips, repository operations/collisions, autosave races, and defensive copies. Only restart/reload proves native/browser persistence end to end; state the tested layer.
