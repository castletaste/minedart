library;

import 'dart:typed_data';

import '../block.dart';
import '../chunk.dart';
import '../liquid.dart';
import '../world.dart';
import 'world_change.dart';

part 'world_tick_engine_behaviors.dart';
part 'world_tick_engine_fluids.dart';
part 'world_tick_engine_sponges.dart';
part 'world_tick_engine_scheduler.dart';

/// Deterministic, bounded block simulation for the finite Classic world.
///
/// Scheduled work is ordered by due tick and insertion sequence. Public
/// [enqueue] calls are neighbor notifications; liquid notifications arm the
/// identity-aware Alpha delay when they are observed. Consequences always use
/// a future due tick, so work created by one [tick] cannot run in that tick.
final class WorldTickEngine {
  WorldTickEngine({
    this.maxQueue = 4096,
    this.maxFluidLevel = LiquidState.maxLevel,
    this.spongeRadius = 2,
    this.tntFuseTicks = 4,
    this.explosionRadius = 3,
  }) : assert(maxQueue > 0),
       assert(maxFluidLevel >= 0 && maxFluidLevel <= LiquidState.maxLevel),
       assert(spongeRadius >= 0),
       assert(tntFuseTicks > 0),
       assert(explosionRadius >= 0);

  final int maxQueue;
  final int maxFluidLevel;
  final int spongeRadius;
  final int tntFuseTicks;
  final int explosionRadius;

  final List<_ScheduledEntry> _heap = [];
  final Map<int, _ScheduledEntry> _scheduled = {};
  final Map<int, int> _fallCooldowns = {};
  final Map<int, int> _tntFuses = {};
  final Set<int> _activeSponges = {};
  VoxelWorld? _spongeIndexWorld;
  bool _spongeIndexInitialized = false;
  final Uint32List _retryWords = Uint32List(
    (_worldChunkCount + _bitsPerRetryWord - 1) ~/ _bitsPerRetryWord,
  );

  int _currentTick = 0;
  int _nextSequence = 0;
  int _retryChunkCount = 0;
  int _droppedUpdates = 0;

  int get currentTick => _currentTick;
  int get pendingCount => _scheduled.length;
  int get retryChunkCount => _retryChunkCount;
  int get primedTntCount => _tntFuses.length;
  int get droppedUpdates => _droppedUpdates;
  bool get isIdle =>
      _scheduled.isEmpty &&
      _retryChunkCount == 0 &&
      _fallCooldowns.isEmpty &&
      _tntFuses.isEmpty;

  /// Schedules one in-bounds neighbor notification for the next app tick.
  ///
  /// Returns false for duplicates, overflow, or out-of-bounds coordinates.
  /// Overflow marks the coordinate's chunk/halo for deterministic retry.
  bool enqueue(int x, int y, int z) {
    if (!VoxelWorld.inBounds(x, y, z)) return false;
    return _scheduleKey(
      worldPositionKey(x, y, z),
      expectedLiquidId: _genericIdentity,
      dueTick: _currentTick + 1,
    );
  }

  /// Schedules a changed block plus its six face-neighbors.
  void enqueueAround(int x, int y, int z) {
    enqueue(x, y, z);
    for (final offset in _faceOffsets) {
      enqueue(x + offset.$1, y + offset.$2, z + offset.$3);
    }
  }

  /// Read-only load/history priming for persisted simulation work.
  ///
  /// Scanning order is chunk index followed by the persisted local voxel
  /// order. Unstable liquids/falling blocks, sponges with nearby water, and TNT
  /// carrying non-zero fuse metadata are scheduled. Capacity overflow is
  /// represented by retry marks, so [isIdle] remains false until reconvergence.
  /// The return value is the number of active entries added by this call.
  int prime(VoxelWorld world) {
    _activeSponges.clear();
    _spongeIndexWorld = world;
    _spongeIndexInitialized = false;
    final before = _scheduled.length;
    for (var chunkIndex = 0; chunkIndex < world.chunks.length; chunkIndex++) {
      final chunk = world.chunks[chunkIndex];
      for (var localIndex = 0; localIndex < ChunkIndex.volume; localIndex++) {
        final raw = chunk.blocks[localIndex];
        final behavior = _behaviorForRaw(raw);
        final (x, y, z) = _worldCoordinates(chunk, localIndex);
        if (behavior == BlockBehavior.sponge) {
          _activeSponges.add(worldPositionKey(x, y, z));
          if (_hasWaterNearby(world, x, y, z)) {
            _scheduleGeneric(x, y, z);
          }
          continue;
        }
        if (behavior == BlockBehavior.falling) {
          if (y > 0 && Blocks.id(world.blockAt(x, y - 1, z)) == Blocks.air) {
            _scheduleGeneric(x, y, z);
          }
          continue;
        }
        if (behavior == BlockBehavior.tnt) {
          final elapsed = Blocks.meta(raw);
          if (elapsed > 0) {
            final key = worldPositionKey(x, y, z);
            _tntFuses.putIfAbsent(
              key,
              () => (tntFuseTicks - elapsed).clamp(1, tntFuseTicks),
            );
            _scheduleGeneric(x, y, z);
          }
          continue;
        }
        if (behavior != BlockBehavior.water && behavior != BlockBehavior.lava) {
          continue;
        }
        if (!_needsFluidUpdate(
          world,
          x,
          y,
          z,
          raw,
          includeSpongeCheck: false,
        )) {
          continue;
        }
        _scheduleLiquid(
          x,
          y,
          z,
          Blocks.id(raw),
          _currentTick + _fluidDelay(Blocks.id(raw)),
        );
      }
    }
    _spongeIndexInitialized = true;
    return _scheduled.length - before;
  }

  /// Clears transient scheduler state, then re-arms work encoded in [world].
  int resetAndPrime(VoxelWorld world) {
    clear();
    return prime(world);
  }

  /// Starts a TNT fuse at this coordinate. Ordinary neighbor scheduling does
  /// not ignite TNT; interaction code and chain reactions call this method.
  bool activateTnt(VoxelWorld world, int x, int y, int z) {
    if (!VoxelWorld.inBounds(x, y, z)) return false;
    if (_behaviorAt(world, x, y, z) != BlockBehavior.tnt) return false;
    final key = worldPositionKey(x, y, z);
    if (_tntFuses.containsKey(key)) return false;
    if (!_hasGenericScheduled(key) && !enqueue(x, y, z)) return false;
    _tntFuses[key] = tntFuseTicks;
    return true;
  }

  WorldChangeSet tick(VoxelWorld world, int budget) {
    if (budget <= 0) return WorldChangeSet.empty();
    _currentTick++;

    // Retry promotion itself only creates future work.
    _promoteRetries(world);

    final builder = WorldChangeSetBuilder(world);
    final workLimit = budget < _maxWorkPerTick ? budget : _maxWorkPerTick;
    var processed = 0;
    while (processed < workLimit) {
      final next = _peekScheduled();
      if (next == null || next.dueTick > _currentTick) break;
      final entry = _popScheduled()!;
      _scheduled.remove(entry.identity);
      _processEntry(world, builder, entry);
      processed++;
    }

    // Entries consumed above make bounded capacity available for marked work.
    _promoteRetries(world);
    return builder.build();
  }

  void clear() {
    _heap.clear();
    _scheduled.clear();
    _fallCooldowns.clear();
    _tntFuses.clear();
    _activeSponges.clear();
    _spongeIndexWorld = null;
    _spongeIndexInitialized = false;
    _retryWords.fillRange(0, _retryWords.length, 0);
    _currentTick = 0;
    _nextSequence = 0;
    _retryChunkCount = 0;
    _droppedUpdates = 0;
  }

  static bool _entryBefore(_ScheduledEntry a, _ScheduledEntry b) =>
      a.dueTick < b.dueTick ||
      (a.dueTick == b.dueTick && a.sequence < b.sequence);

  static int _scheduleIdentity(int key, int expectedLiquidId) =>
      key * _identityStride + expectedLiquidId;

  static int _fluidDelay(int id) =>
      id == Blocks.lava ? _lavaDelayTicks : _waterDelayTicks;

  static int _fluidDecay(int id) => id == Blocks.lava ? 2 : 1;

  static bool _lavaLevelAdvanceAllowed(
    int seed,
    int x,
    int y,
    int z,
    int dueTick,
  ) {
    var hash = seed & _uint32Mask;
    hash ^= (x * 0x9E3779B1) & _uint32Mask;
    hash ^= (y * 0x85EBCA6B) & _uint32Mask;
    hash ^= (z * 0xC2B2AE35) & _uint32Mask;
    hash ^= hash >>> 16;
    hash = _multiplyUint32(hash, 0x7FEB352D);
    hash ^= hash >>> 15;
    // Advancing due ticks rotate the low two bits, guaranteeing eventual
    // progress while retaining one keyed outcome in four.
    return ((hash + dueTick ~/ _lavaDelayTicks) & 3) == 0;
  }

  /// Exact low 32 bits of a product on both VM/Wasm and dart2js.
  ///
  /// Splitting into 16-bit limbs keeps every intermediate below JavaScript's
  /// exact-integer limit instead of relying on a ~64-bit double product.
  static int _multiplyUint32(int left, int right) {
    final leftLow = left & 0xFFFF;
    final rightLow = right & 0xFFFF;
    final low = leftLow * rightLow;
    final middle =
        (((left >>> 16) * rightLow + leftLow * (right >>> 16)) & 0xFFFF) *
        0x10000;
    return ((low + middle) & _uint32Mask) >>> 0;
  }

  static BlockBehavior _behaviorAt(VoxelWorld world, int x, int y, int z) {
    if (!VoxelWorld.inBounds(x, y, z)) return BlockBehavior.plain;
    return _behaviorForRaw(world.blockAt(x, y, z));
  }

  static BlockBehavior _behaviorForRaw(int raw) {
    final id = Blocks.id(raw);
    if (id <= Blocks.air || id >= blockDefs.length) return BlockBehavior.plain;
    return blockDefs[id]?.behavior ?? BlockBehavior.plain;
  }

  static (int, int, int) _decodePosition(int key) {
    final y = key ~/ (WorldDims.worldBlocksX * WorldDims.worldBlocksZ);
    final horizontal = key % (WorldDims.worldBlocksX * WorldDims.worldBlocksZ);
    final z = horizontal ~/ WorldDims.worldBlocksX;
    final x = horizontal % WorldDims.worldBlocksX;
    return (x, y, z);
  }

  static (int, int, int) _worldCoordinates(Chunk chunk, int localIndex) {
    final y = localIndex ~/ ChunkIndex.sliceArea;
    final horizontal = localIndex % ChunkIndex.sliceArea;
    final z = horizontal ~/ WorldDims.chunkSize;
    final x = horizontal % WorldDims.chunkSize;
    return (
      chunk.cx * WorldDims.chunkSize + x,
      chunk.cy * WorldDims.chunkSize + y,
      chunk.cz * WorldDims.chunkSize + z,
    );
  }
}

final class _ScheduledEntry {
  const _ScheduledEntry({
    required this.key,
    required this.expectedLiquidId,
    required this.dueTick,
    required this.sequence,
  });

  final int key;
  final int expectedLiquidId;
  final int dueTick;
  final int sequence;

  int get identity => WorldTickEngine._scheduleIdentity(key, expectedLiquidId);
}

const _faceOffsets = <(int, int, int)>[
  (1, 0, 0),
  (-1, 0, 0),
  (0, 1, 0),
  (0, -1, 0),
  (0, 0, 1),
  (0, 0, -1),
];

const _horizontalOffsets = <(int, int, int)>[
  (1, 0, 0),
  (-1, 0, 0),
  (0, 0, 1),
  (0, 0, -1),
];

const _lavaContactOffsets = <(int, int, int)>[
  (1, 0, 0),
  (-1, 0, 0),
  (0, 0, 1),
  (0, 0, -1),
  (0, 1, 0),
];

// A water notification can trigger lava beside it or immediately below it.
// Lava above the water intentionally sees water below and must not react.
const _waterTriggeredLavaOffsets = <(int, int, int)>[
  (1, 0, 0),
  (-1, 0, 0),
  (0, 0, 1),
  (0, 0, -1),
  (0, -1, 0),
];

const int _waterDelayTicks = 5;
const int _lavaDelayTicks = 30;
const int _fallIntervalTicks = 4;
const int _dropSearchDepth = 4;
const int _noFlowCost = 1000;
const int _maxWorkPerTick = 256;
const int _retryChunksPerTick = 4;
const int _bitsPerRetryWord = 32;
const int _identityStride = 1 << 12;
const int _genericIdentity = 0;
const int _uint32Mask = 0xFFFFFFFF;
const int _worldChunkCount =
    WorldDims.worldChunksX * WorldDims.worldChunksY * WorldDims.worldChunksZ;
