# Minedart Alpha liquid profile 0.4

Status: approved for production implementation, including the additive
`Blocks.obsidian = 33` registry entry.

## Historical reference

The project pins Java Edition Alpha v1.2.6 because it is the final Alpha
release and provides a coherent registry/block set. The liquid algorithm is not
unique to that build: normalized flowing-liquid code is unchanged across
a1.2.3_04, a1.2.5, a1.2.6 and b1.0.

Primary artifact:

- Mojang version metadata SHA-1
  `1c888e4d8aed380db25aeb3835f5918297bb5e3a`;
- official a1.2.6 client JAR SHA-1
  `a68c817afd6c05c253ba5462287c2c19bbb57935`;
- official JAR SHA-256
  `63276bf2617068ffbaf2a1992d1f06f9339c96c21991eafc9583d5f3e7074b9c`.

Community mappings are navigation only. State transitions and constants were
checked against the official obfuscated bytecode (`ld`, `ja`, `ir`, `bk`,
`cy`, `hf`, `pd`). No Mojang source or asset is copied into Minedart.

## Profile: Alpha topology plus Minedart reliability

The user-approved single-ID constraint is retained:

```text
meta 0       source
meta 1..7    horizontal level
meta 8..15   falling flag | retained level
level        meta & 7
falling      (meta & 8) != 0
```

Alpha's separate moving/still block IDs become scheduler state. A stable
liquid has no due update; a neighbor edit schedules it again. On load a bounded
deterministic scan primes only unstable/contact cells. In-flight timer state is
not persisted, but the topology deterministically reconverges in MDRT2.

Declared, intentional divergences from byte-exact Alpha:

- one block ID per liquid instead of flowing/still ID pairs;
- sponge remains active in Chebyshev radius 2;
- bounded overflow is retryable instead of permanently dropped;
- lava's random delay uses a deterministic keyed sample and explicit retry;
- lava receives current as well as drag because Minedart has no health/survival
  layer and the approved scope requires physical liquid behavior for both;
- one active liquid cascade is one undo group.

## Exact topology rules

- The app simulation clock is 20 Hz.
- Water delay is 5 ticks and horizontal decay is 1: source levels reach 1–7.
- Lava delay is 30 ticks and horizontal decay is 2: a flat source reaches
  levels 2, 4 and 6. A blocked falling column spreads as 1, 3, 5 and 7.
- Falling cells are effective level zero to neighbors.
- A non-falling downward write sets bit 3; a falling write preserves metadata.
- Downward flow has priority and prevents horizontal spread in that update.
- When down is blocked, search four horizontal directions to depth 4, exclude
  the reverse edge, and flow into every direction tied at minimum drop cost.
- Recompute level from horizontal upstream cells and same-fluid cell above;
  unsupported flow retracts to air.
- Two horizontal water sources create a source only with opaque support or
  source water below. Lava never forms an infinite source.
- Non-solid replaceable plants are displaced; solid blocks and sponge block
  flow.

For lava level increases, a deterministic hash of world seed, coordinate and
due tick advances on one of four outcomes. The other three explicitly
reschedule; postponement cannot freeze topology or become a lost update.

## Contact matrix

Only a lava cell reacts. It checks four horizontal neighbors and the cell
above, never below. Water is never transformed.

```text
lava meta 0      + water -> obsidian
lava meta 1..4   + water -> cobblestone
lava meta 5..15  + water -> unchanged
```

The approved additive registry extension is:

- `Blocks.obsidian = 33`;
- `Blocks.count = 34`;
- `Tiles.obsidian = 36` plus one original generated atlas tile.

The Uint16 block layout, 12-bit ID, 4-bit metadata, chunk order and MDRT2
format remain unchanged. Older builds cannot read worlds containing ID 33, so
this is additive forward use, not backward readability by old binaries.

## Retryable due scheduler

- Due entries order by `(dueTick, insertionSequence)`.
- Active capacity remains 4096 and per-app-tick work budget remains 256.
- Deduplicate by coordinate and expected liquid identity; revalidate at pop.
- Work created during one tick cannot execute in that same tick.
- On capacity pressure mark the affected chunk/halo in a fixed 1024-chunk
  retry bitset.
- A bounded scanner promotes marked work in chunk-index/local-index order as
  capacity opens.
- `isIdle` includes due entries and retry marks.
- Overflow must converge to the same final topology as an unbounded reference
  scheduler.

## Rendering and physics

Fluid surface height follows Alpha metadata. Each top corner averages its 2x2
column neighborhood; a same-fluid cell above produces height 1, and source or
falling samples receive the Alpha 11x weight. Water and lava share geometry but
retain separate material/atlas behavior. Existing 18-cube snapshot halos and
the 20-float vertex ABI are sufficient.

Immersion uses the actual surface, not a full voxel. Flow vectors derive from
neighbor level gradients and falling columns. The Alpha 20 Hz constants are
converted to the 60 Hz fixed physics step:

- water drag derives from `0.8^(1/3)` per physics step;
- lava drag derives from `0.5^(1/3)`;
- current and buoyancy impulses are time-scaled rather than copied literally.

No damage, fire, health or survival state is introduced.

## Acceptance tests

- metadata 0–15 and falling/landing transitions;
- exact water/lava delays and flat ranges;
- source removal, obstruction reflow and full retraction;
- depth-4 drop choice and equal-cost ties;
- infinite-water positive/negative/support cases and no infinite lava;
- plant displacement, solid blocking and active sponge/refill;
- complete contact matrix, order independence and no reaction from water below;
- capacity 1/2 overflow progress and unbounded-reference final equality;
- deterministic keyed lava retries and save/load reconvergence;
- one cascade/undo group and load priming without undo history;
- MDRT2 raw metadata/obsidian round-trip and unchanged legacy fixtures;
- corner heights, chunk-border continuity, sides and same-fluid culling;
- actual-height immersion, current direction, water/lava drag and swimming;
- full core/app analyze/tests plus visible macOS and Chrome WebGPU water/lava QA.
