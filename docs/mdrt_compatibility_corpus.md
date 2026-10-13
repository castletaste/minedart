# MDRT compatibility corpus

The persistence tests keep a small deterministic corpus for every format the
runtime accepts:

- MDRT1: legacy seed header and gzip block payload, migrated in memory to the
  current metadata version;
- MDRT2: current metadata section plus bounded gzip block payload. The checked-in
  MDRT2 file pins the current encoder shape; it is not a historical pre-v2
  fixture;
- malformed section lengths, truncated headers, truncated payloads, and
  unsupported compressed data.

The immutable fixtures live in `app/test/data/worlds/fixtures/`. The test
checks their decoded block values, metadata migration, malformed section
lengths, truncated headers and payloads, and a corrupted gzip trailer. New
format versions should add one fixture and one explicit migration assertion
before the codec's `currentFormatVersion` changes.
