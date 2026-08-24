library;

import 'dart:collection';

import '../block.dart';
import '../chunk.dart';
import '../world.dart';
import 'world_change.dart';

/// Deterministic, bounded block simulation for the finite Classic world.
///
/// Work is FIFO and coordinate-deduplicated. A tick processes at most the
/// queue entries that existed when it began, so consequences always advance
/// on a later tick and the supplied [budget] remains a hard work bound.
final class WorldTickEngine {
  WorldTickEngine({
    this.maxQueue = 4096,
    this.maxFluidLevel = 7,
    this.spongeRadius = 2,
    this.tntFuseTicks = 4,
    this.explosionRadius = 3,
  }) : assert(maxQueue > 0),
       assert(maxFluidLevel >= 0 && maxFluidLevel <= 15),
       assert(spongeRadius >= 0),
       assert(tntFuseTicks > 0),
       assert(explosionRadius >= 0);

  final int maxQueue;
  final int maxFluidLevel;
  final int spongeRadius;
  final int tntFuseTicks;
  final int explosionRadius;

  final Queue<int> _queue = Queue<int>();
  final Set<int> _queued = {};
  // Every cooldown entry owns the matching queued coordinate, so this state is
  // bounded by [maxQueue] without a second eviction policy.
  final Map<int, int> _fallCooldowns = {};
  final Map<int, int> _tntFuses = {};
  int _droppedUpdates = 0;

  int get pendingCount => _queue.length;
  int get primedTntCount => _tntFuses.length;
  int get droppedUpdates => _droppedUpdates;
  bool get isIdle =>
      _queue.isEmpty && _fallCooldowns.isEmpty && _tntFuses.isEmpty;

  /// Schedules one in-bounds block. Returns false for duplicates, overflow,
  /// or out-of-bounds coordinates.
  bool enqueue(int x, int y, int z) {
    if (!VoxelWorld.inBounds(x, y, z)) return false;
    final key = worldPositionKey(x, y, z);
    if (_queued.contains(key)) return false;
    if (_queue.length >= maxQueue) {
      _droppedUpdates++;
      return false;
    }
    _queue.addLast(key);
    _queued.add(key);
    return true;
  }

  /// Schedules a changed block plus its six face-neighbors.
  void enqueueAround(int x, int y, int z) {
    enqueue(x, y, z);
    for (final offset in _faceOffsets) {
      enqueue(x + offset.$1, y + offset.$2, z + offset.$3);
    }
  }

  /// Starts a TNT fuse at this coordinate. Ordinary neighbor scheduling does
  /// not ignite TNT; interaction code and chain reactions call this method.
  bool activateTnt(VoxelWorld world, int x, int y, int z) {
    if (!VoxelWorld.inBounds(x, y, z)) return false;
    if (_behaviorAt(world, x, y, z) != BlockBehavior.tnt) return false;
    final key = worldPositionKey(x, y, z);
    if (_tntFuses.containsKey(key)) return false;
    if (!_queued.contains(key) && !enqueue(x, y, z)) return false;
    _tntFuses[key] = tntFuseTicks;
    return true;
  }

  WorldChangeSet tick(VoxelWorld world, int budget) {
    if (budget <= 0 || _queue.isEmpty) return WorldChangeSet.empty();
    final builder = WorldChangeSetBuilder(world);
    final work = budget < _queue.length ? budget : _queue.length;

    for (var i = 0; i < work; i++) {
      final key = _queue.removeFirst();
      _queued.remove(key);
      final (x, y, z) = _decodePosition(key);
      _process(world, builder, key, x, y, z);
    }
    return builder.build();
  }

  void clear() {
    _queue.clear();
    _queued.clear();
    _fallCooldowns.clear();
    _tntFuses.clear();
    _droppedUpdates = 0;
  }

  void _process(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    int key,
    int x,
    int y,
    int z,
  ) {
    final raw = world.blockAt(x, y, z);
    final id = Blocks.id(raw);
    final definition = id < blockDefs.length ? blockDefs[id] : null;
    final behavior = definition?.behavior ?? BlockBehavior.plain;

    if (behavior != BlockBehavior.falling) _fallCooldowns.remove(key);
    if (behavior != BlockBehavior.tnt) _tntFuses.remove(key);

    switch (behavior) {
      case BlockBehavior.falling:
        _fall(world, builder, key, x, y, z, raw);
      case BlockBehavior.water:
      case BlockBehavior.lava:
        _spreadFluid(world, builder, x, y, z, raw, behavior);
      case BlockBehavior.sponge:
        _absorbWater(world, builder, x, y, z);
      case BlockBehavior.tnt:
        if (_tntFuses.containsKey(key)) {
          _tickTnt(world, builder, key, x, y, z);
        }
      case BlockBehavior.plain:
      case BlockBehavior.plant:
        break;
    }
  }

  void _fall(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    int key,
    int x,
    int y,
    int z,
    int raw,
  ) {
    if (y == 0 || Blocks.id(world.blockAt(x, y - 1, z)) != Blocks.air) {
      _fallCooldowns.remove(key);
      return;
    }

    final remaining = _fallCooldowns[key] ?? _fallIntervalTicks;
    if (remaining > 1) {
      _fallCooldowns[key] = remaining - 1;
      // This tick removed [key] before processing it and waiting performs no
      // writes, so the bounded queue always has room for this continuation.
      enqueue(x, y, z);
      assert(
        _queued.contains(key),
        'An unsupported falling block must stay scheduled.',
      );
      return;
    }

    _fallCooldowns.remove(key);
    _set(builder, x, y - 1, z, raw);
    _set(builder, x, y, z, Blocks.air);
  }

  void _spreadFluid(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    int x,
    int y,
    int z,
    int raw,
    BlockBehavior behavior,
  ) {
    final opposite = behavior == BlockBehavior.water
        ? BlockBehavior.lava
        : BlockBehavior.water;

    // Contact is deterministic: the lava cell becomes cobblestone regardless
    // of which fluid update reaches the pair first.
    for (final offset in _faceOffsets) {
      final nx = x + offset.$1;
      final ny = y + offset.$2;
      final nz = z + offset.$3;
      if (!VoxelWorld.inBounds(nx, ny, nz)) continue;
      if (_behaviorAt(world, nx, ny, nz) != opposite) continue;
      if (behavior == BlockBehavior.lava) {
        _set(builder, x, y, z, Blocks.cobblestone);
        return;
      }
      _set(builder, nx, ny, nz, Blocks.cobblestone);
    }

    if (_behaviorAt(world, x, y, z) != behavior) return;
    final id = Blocks.id(raw);
    final level = Blocks.meta(raw).clamp(0, maxFluidLevel);

    if (y > 0 && _canFlowInto(world, x, y - 1, z, behavior, level)) {
      _set(builder, x, y - 1, z, Blocks.pack(id, level));
      return;
    }
    if (level >= maxFluidLevel) return;

    final nextRaw = Blocks.pack(id, level + 1);
    for (final offset in _horizontalOffsets) {
      final nx = x + offset.$1;
      final nz = z + offset.$3;
      if (_canFlowInto(world, nx, y, nz, behavior, level + 1)) {
        _set(builder, nx, y, nz, nextRaw);
      }
    }
  }

  bool _canFlowInto(
    VoxelWorld world,
    int x,
    int y,
    int z,
    BlockBehavior behavior,
    int newLevel,
  ) {
    if (!VoxelWorld.inBounds(x, y, z)) return false;
    if (behavior == BlockBehavior.water && _hasSpongeNearby(world, x, y, z)) {
      return false;
    }
    final target = world.blockAt(x, y, z);
    if (Blocks.id(target) == Blocks.air) return true;
    return _behaviorForRaw(target) == behavior &&
        Blocks.meta(target) > newLevel;
  }

  void _absorbWater(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    int x,
    int y,
    int z,
  ) {
    for (var dy = -spongeRadius; dy <= spongeRadius; dy++) {
      for (var dz = -spongeRadius; dz <= spongeRadius; dz++) {
        for (var dx = -spongeRadius; dx <= spongeRadius; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          final nz = z + dz;
          if (!VoxelWorld.inBounds(nx, ny, nz)) continue;
          if (_behaviorAt(world, nx, ny, nz) == BlockBehavior.water) {
            _set(builder, nx, ny, nz, Blocks.air);
          }
        }
      }
    }
  }

  bool _hasSpongeNearby(VoxelWorld world, int x, int y, int z) {
    for (var dy = -spongeRadius; dy <= spongeRadius; dy++) {
      for (var dz = -spongeRadius; dz <= spongeRadius; dz++) {
        for (var dx = -spongeRadius; dx <= spongeRadius; dx++) {
          if (_behaviorAt(world, x + dx, y + dy, z + dz) ==
              BlockBehavior.sponge) {
            return true;
          }
        }
      }
    }
    return false;
  }

  void _tickTnt(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    int key,
    int x,
    int y,
    int z,
  ) {
    final remaining = _tntFuses[key]!;
    if (remaining > 1) {
      _tntFuses[key] = remaining - 1;
      final raw = world.blockAt(x, y, z);
      final elapsed = (tntFuseTicks - remaining + 1).clamp(0, 15);
      _set(builder, x, y, z, Blocks.pack(Blocks.id(raw), elapsed));
      // A restored world may already contain [elapsed] in block metadata. In
      // that case _set is intentionally a no-op, but the live fuse still needs
      // a future FIFO entry. The entry removed by this tick guarantees one
      // free bounded-queue slot; when _set changed metadata, enqueueAround has
      // already inserted this same key first and this call simply deduplicates.
      enqueue(x, y, z);
      assert(_queued.contains(key), 'An active TNT fuse must stay scheduled.');
      return;
    }
    _tntFuses.remove(key);
    _explode(world, builder, x, y, z);
  }

  void _explode(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    int x,
    int y,
    int z,
  ) {
    final radiusSquared = explosionRadius * explosionRadius;
    for (var dy = -explosionRadius; dy <= explosionRadius; dy++) {
      for (var dz = -explosionRadius; dz <= explosionRadius; dz++) {
        for (var dx = -explosionRadius; dx <= explosionRadius; dx++) {
          if (dx * dx + dy * dy + dz * dz > radiusSquared) continue;
          final nx = x + dx;
          final ny = y + dy;
          final nz = z + dz;
          if (!VoxelWorld.inBounds(nx, ny, nz)) continue;
          final targetRaw = world.blockAt(nx, ny, nz);
          final targetId = Blocks.id(targetRaw);
          if (targetId == Blocks.air) continue;
          final definition = targetId < blockDefs.length
              ? blockDefs[targetId]
              : null;
          if (definition == null || !definition.breakable) continue;
          if (definition.behavior == BlockBehavior.tnt &&
              (nx != x || ny != y || nz != z)) {
            activateTnt(world, nx, ny, nz);
            continue;
          }
          _set(builder, nx, ny, nz, Blocks.air);
        }
      }
    }
  }

  void _set(WorldChangeSetBuilder builder, int x, int y, int z, int raw) {
    if (builder.set(x, y, z, raw)) enqueueAround(x, y, z);
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

/// The app advances block simulation every 50 ms, so falling blocks move one
/// cell per roughly 200 ms without exposing transient state through metadata.
const int _fallIntervalTicks = 4;
