library;

import 'dart:typed_data';

import '../block.dart';
import '../chunk.dart';
import '../liquid.dart';
import '../world.dart';
import 'world_change.dart';

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

  void _processEntry(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    _ScheduledEntry entry,
  ) {
    final (x, y, z) = _decodePosition(entry.key);
    final raw = world.blockAt(x, y, z);
    if (entry.expectedLiquidId != _genericIdentity) {
      if (Blocks.id(raw) != entry.expectedLiquidId) return;
      _processFluidDue(world, builder, x, y, z, raw);
      return;
    }

    final id = Blocks.id(raw);
    final definition = id < blockDefs.length ? blockDefs[id] : null;
    final behavior = definition?.behavior ?? BlockBehavior.plain;

    _reconcileSpongeState(world, x, y, z, behavior);

    if (behavior != BlockBehavior.falling) {
      _fallCooldowns.remove(entry.key);
    }
    if (behavior != BlockBehavior.tnt) _tntFuses.remove(entry.key);

    switch (behavior) {
      case BlockBehavior.falling:
        _fall(world, builder, entry.key, x, y, z, raw);
      case BlockBehavior.water:
      case BlockBehavior.lava:
        _observeFluidNeighborChange(world, builder, x, y, z, raw);
      case BlockBehavior.sponge:
        _absorbWater(world, builder, x, y, z);
      case BlockBehavior.tnt:
        if (_tntFuses.containsKey(entry.key)) {
          _tickTnt(world, builder, entry.key, x, y, z);
        }
      case BlockBehavior.plain:
      case BlockBehavior.plant:
        break;
    }
  }

  void _observeFluidNeighborChange(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    int x,
    int y,
    int z,
    int raw,
  ) {
    final id = Blocks.id(raw);
    if (id == Blocks.lava) {
      if (_solidifyLava(world, builder, x, y, z)) return;
    } else {
      _solidifyLavaTouchingWater(world, builder, x, y, z);
    }

    if (Blocks.id(world.blockAt(x, y, z)) != id) return;
    // The notification itself consumed the first elapsed app tick.
    final dueTick = _currentTick + _fluidDelay(id) - 1;
    _scheduleLiquid(x, y, z, id, dueTick);
  }

  void _processFluidDue(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    int x,
    int y,
    int z,
    int raw,
  ) {
    final id = Blocks.id(raw);
    if (id == Blocks.lava) {
      if (_solidifyLava(world, builder, x, y, z)) return;
    } else {
      _solidifyLavaTouchingWater(world, builder, x, y, z);
    }
    final current = world.blockAt(x, y, z);
    if (Blocks.id(current) != id) return;
    _updateFluidTopology(world, builder, x, y, z, current);
  }

  void _updateFluidTopology(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    int x,
    int y,
    int z,
    int raw,
  ) {
    final id = Blocks.id(raw);
    var metadata = Blocks.meta(raw);

    if (id == Blocks.water && _hasSpongeNearby(world, x, y, z)) {
      _set(builder, x, y, z, Blocks.air);
      return;
    }

    if (metadata != 0) {
      final desired = _recomputedFluidMetadata(world, x, y, z, id);
      if (desired == null) {
        _set(builder, x, y, z, Blocks.air);
        return;
      }
      if (id == Blocks.lava &&
          metadata < LiquidState.fallingBit &&
          desired < LiquidState.fallingBit &&
          desired > metadata &&
          !_lavaLevelAdvanceAllowed(world.seed, x, y, z, _currentTick)) {
        _scheduleLiquid(x, y, z, id, _currentTick + _lavaDelayTicks);
        return;
      }
      if (desired != metadata) {
        metadata = desired;
        _set(builder, x, y, z, Blocks.pack(id, metadata));
      }
    }

    final falling = (metadata & LiquidState.fallingBit) != 0;
    final level = metadata & LiquidState.levelMask;
    final downMetadata = falling ? metadata : metadata | LiquidState.fallingBit;
    if (y > 0 && _canReceiveFluid(world, x, y - 1, z, id, downMetadata)) {
      _set(builder, x, y - 1, z, Blocks.pack(id, downMetadata));
      return;
    }

    // Alpha sources spread even above an existing liquid column. Other flow
    // spreads only where the block below actually blocks downward movement.
    if (metadata != 0 && !_blocksFluid(world, x, y - 1, z)) return;

    final nextLevel = falling ? 1 : level + _fluidDecay(id);
    if (nextLevel > maxFluidLevel || nextLevel > LiquidState.maxLevel) return;
    final nextRaw = Blocks.pack(id, nextLevel);
    final minimumCost = _minimumDropCost(world, x, y, z, id, nextLevel);
    for (
      var direction = 0;
      direction < _horizontalOffsets.length;
      direction++
    ) {
      final offset = _horizontalOffsets[direction];
      final nx = x + offset.$1;
      final nz = z + offset.$3;
      if (!_canReceiveFluid(world, nx, y, nz, id, nextLevel)) continue;
      final cost = _dropCostForDirection(
        world,
        x,
        y,
        z,
        id,
        nextLevel,
        direction,
      );
      if (cost == minimumCost) _set(builder, nx, y, nz, nextRaw);
    }
  }

  int? _recomputedFluidMetadata(
    VoxelWorld world,
    int x,
    int y,
    int z,
    int fluidId,
  ) {
    var minimumCandidate = _noFlowCost;
    var adjacentSources = 0;
    for (final offset in _horizontalOffsets) {
      final neighbor = world.blockAt(x + offset.$1, y, z + offset.$3);
      if (Blocks.id(neighbor) != fluidId) continue;
      final neighborMetadata = Blocks.meta(neighbor);
      if (neighborMetadata == 0) adjacentSources++;
      final candidate = neighborMetadata >= LiquidState.fallingBit
          ? 1
          : neighborMetadata + _fluidDecay(fluidId);
      if (candidate < minimumCandidate) minimumCandidate = candidate;
    }

    int? desired;
    if (minimumCandidate != _noFlowCost) {
      if (minimumCandidate <= maxFluidLevel &&
          minimumCandidate <= LiquidState.maxLevel) {
        desired = minimumCandidate;
      }
    }

    if (y + 1 < WorldDims.worldBlocksY) {
      final above = world.blockAt(x, y + 1, z);
      if (Blocks.id(above) == fluidId) {
        final aboveMetadata = Blocks.meta(above);
        desired = aboveMetadata >= LiquidState.fallingBit
            ? aboveMetadata
            : aboveMetadata | LiquidState.fallingBit;
      }
    }

    if (fluidId == Blocks.water &&
        adjacentSources >= 2 &&
        _supportsInfiniteWater(world, x, y, z)) {
      desired = 0;
    }
    return desired;
  }

  bool _supportsInfiniteWater(VoxelWorld world, int x, int y, int z) {
    if (y == 0) return true;
    final below = world.blockAt(x, y - 1, z);
    if (Blocks.id(below) == Blocks.water && Blocks.meta(below) == 0) {
      return true;
    }
    final belowId = Blocks.id(below);
    if (belowId <= Blocks.air || belowId >= blockDefs.length) return false;
    return blockDefs[belowId]?.opaque ?? false;
  }

  int _minimumDropCost(
    VoxelWorld world,
    int x,
    int y,
    int z,
    int fluidId,
    int horizontalMetadata,
  ) {
    var minimum = _noFlowCost;
    for (
      var direction = 0;
      direction < _horizontalOffsets.length;
      direction++
    ) {
      final cost = _dropCostForDirection(
        world,
        x,
        y,
        z,
        fluidId,
        horizontalMetadata,
        direction,
      );
      if (cost < minimum) minimum = cost;
    }
    return minimum;
  }

  int _dropCostForDirection(
    VoxelWorld world,
    int x,
    int y,
    int z,
    int fluidId,
    int horizontalMetadata,
    int direction,
  ) {
    final offset = _horizontalOffsets[direction];
    final nx = x + offset.$1;
    final nz = z + offset.$3;
    if (!_canReceiveFluid(world, nx, y, nz, fluidId, horizontalMetadata)) {
      return _noFlowCost;
    }
    final downMetadata = horizontalMetadata | LiquidState.fallingBit;
    if (y > 0 &&
        _canReceiveFluid(world, nx, y - 1, nz, fluidId, downMetadata)) {
      return 0;
    }
    return _searchDropCost(
      world,
      nx,
      y,
      nz,
      fluidId,
      horizontalMetadata,
      depth: 1,
      reverseDirection: direction ^ 1,
    );
  }

  int _searchDropCost(
    VoxelWorld world,
    int x,
    int y,
    int z,
    int fluidId,
    int horizontalMetadata, {
    required int depth,
    required int reverseDirection,
  }) {
    var minimum = _noFlowCost;
    for (
      var direction = 0;
      direction < _horizontalOffsets.length;
      direction++
    ) {
      if (direction == reverseDirection) continue;
      final offset = _horizontalOffsets[direction];
      final nx = x + offset.$1;
      final nz = z + offset.$3;
      if (!_canReceiveFluid(world, nx, y, nz, fluidId, horizontalMetadata)) {
        continue;
      }
      final downMetadata = horizontalMetadata | LiquidState.fallingBit;
      if (y > 0 &&
          _canReceiveFluid(world, nx, y - 1, nz, fluidId, downMetadata)) {
        if (depth < minimum) minimum = depth;
        continue;
      }
      if (depth >= _dropSearchDepth) continue;
      final recursive = _searchDropCost(
        world,
        nx,
        y,
        nz,
        fluidId,
        horizontalMetadata,
        depth: depth + 1,
        reverseDirection: direction ^ 1,
      );
      if (recursive < minimum) minimum = recursive;
    }
    return minimum;
  }

  bool _canReceiveFluid(
    VoxelWorld world,
    int x,
    int y,
    int z,
    int fluidId,
    int incomingMetadata,
  ) {
    if (!VoxelWorld.inBounds(x, y, z)) return false;
    if (fluidId == Blocks.water && _hasSpongeNearby(world, x, y, z)) {
      return false;
    }
    final target = world.blockAt(x, y, z);
    final targetId = Blocks.id(target);
    if (targetId == Blocks.air) return true;
    if (_behaviorForRaw(target) == BlockBehavior.plant) return true;
    if (targetId != fluidId) return false;

    final targetMetadata = Blocks.meta(target);
    if (targetMetadata == incomingMetadata || targetMetadata == 0) return false;
    final incomingFalling = incomingMetadata >= LiquidState.fallingBit;
    final targetFalling = targetMetadata >= LiquidState.fallingBit;
    if (incomingFalling) {
      if (!targetFalling) return true;
      return (incomingMetadata & LiquidState.levelMask) <
          (targetMetadata & LiquidState.levelMask);
    }
    if (targetFalling) return false;
    return incomingMetadata < targetMetadata;
  }

  bool _blocksFluid(VoxelWorld world, int x, int y, int z) {
    if (!VoxelWorld.inBounds(x, y, z)) return true;
    final raw = world.blockAt(x, y, z);
    final behavior = _behaviorForRaw(raw);
    if (behavior == BlockBehavior.plant) return false;
    final id = Blocks.id(raw);
    if (id <= Blocks.air || id >= blockDefs.length) return false;
    final definition = blockDefs[id];
    return definition?.solid == true || behavior == BlockBehavior.sponge;
  }

  bool _needsFluidUpdate(
    VoxelWorld world,
    int x,
    int y,
    int z,
    int raw, {
    bool includeSpongeCheck = true,
  }) {
    final id = Blocks.id(raw);
    if (!LiquidState.isLiquidId(id)) return false;
    if (id == Blocks.lava && _lavaHasWaterContact(world, x, y, z)) {
      return true;
    }
    if (id == Blocks.water &&
        includeSpongeCheck &&
        _hasSpongeNearby(world, x, y, z)) {
      return true;
    }

    final metadata = Blocks.meta(raw);
    if (metadata != 0) {
      final desired = _recomputedFluidMetadata(world, x, y, z, id);
      if (desired == null || desired != metadata) return true;
    }

    final falling = metadata >= LiquidState.fallingBit;
    final downMetadata = falling ? metadata : metadata | LiquidState.fallingBit;
    if (y > 0 && _canReceiveFluid(world, x, y - 1, z, id, downMetadata)) {
      return true;
    }
    if (metadata != 0 && !_blocksFluid(world, x, y - 1, z)) return false;
    final nextLevel = falling
        ? 1
        : (metadata & LiquidState.levelMask) + _fluidDecay(id);
    if (nextLevel > maxFluidLevel || nextLevel > LiquidState.maxLevel) {
      return false;
    }
    for (final offset in _horizontalOffsets) {
      if (_canReceiveFluid(
        world,
        x + offset.$1,
        y,
        z + offset.$3,
        id,
        nextLevel,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _solidifyLava(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    int x,
    int y,
    int z,
  ) {
    final raw = world.blockAt(x, y, z);
    if (Blocks.id(raw) != Blocks.lava) return false;
    final metadata = Blocks.meta(raw);
    if (metadata > 4 || !_lavaHasWaterContact(world, x, y, z)) return false;
    _set(
      builder,
      x,
      y,
      z,
      metadata == 0 ? Blocks.obsidian : Blocks.cobblestone,
    );
    return true;
  }

  bool _lavaHasWaterContact(VoxelWorld world, int x, int y, int z) {
    for (final offset in _lavaContactOffsets) {
      if (Blocks.id(
            world.blockAt(x + offset.$1, y + offset.$2, z + offset.$3),
          ) ==
          Blocks.water) {
        return true;
      }
    }
    return false;
  }

  void _solidifyLavaTouchingWater(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    int x,
    int y,
    int z,
  ) {
    for (final offset in _waterTriggeredLavaOffsets) {
      _solidifyLava(
        world,
        builder,
        x + offset.$1,
        y + offset.$2,
        z + offset.$3,
      );
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
      enqueue(x, y, z);
      assert(
        _hasGenericScheduled(key),
        'An unsupported falling block must stay scheduled.',
      );
      return;
    }

    _fallCooldowns.remove(key);
    _set(builder, x, y - 1, z, raw);
    _set(builder, x, y, z, Blocks.air);
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

  bool _hasWaterNearby(VoxelWorld world, int x, int y, int z) {
    for (var dy = -spongeRadius; dy <= spongeRadius; dy++) {
      for (var dz = -spongeRadius; dz <= spongeRadius; dz++) {
        for (var dx = -spongeRadius; dx <= spongeRadius; dx++) {
          if (Blocks.id(world.blockAt(x + dx, y + dy, z + dz)) ==
              Blocks.water) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool _hasSpongeNearby(VoxelWorld world, int x, int y, int z) {
    _ensureSpongeIndex(world);
    if (_activeSponges.isEmpty) return false;
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

  void _ensureSpongeIndex(VoxelWorld world) {
    if (identical(_spongeIndexWorld, world) && _spongeIndexInitialized) return;
    _activeSponges.clear();
    _spongeIndexWorld = world;
    for (final chunk in world.chunks) {
      for (var localIndex = 0; localIndex < ChunkIndex.volume; localIndex++) {
        if (_behaviorForRaw(chunk.blocks[localIndex]) != BlockBehavior.sponge) {
          continue;
        }
        final (x, y, z) = _worldCoordinates(chunk, localIndex);
        _activeSponges.add(worldPositionKey(x, y, z));
      }
    }
    _spongeIndexInitialized = true;
  }

  void _reconcileSpongeState(
    VoxelWorld world,
    int x,
    int y,
    int z,
    BlockBehavior currentBehavior, {
    int? previousRaw,
  }) {
    if (!identical(_spongeIndexWorld, world)) {
      _activeSponges.clear();
      _spongeIndexWorld = world;
      _spongeIndexInitialized = false;
    }
    final key = worldPositionKey(x, y, z);
    if (currentBehavior == BlockBehavior.sponge) {
      _activeSponges.add(key);
      return;
    }

    final removedByInternalWrite =
        previousRaw != null &&
        _behaviorForRaw(previousRaw) == BlockBehavior.sponge;
    final removedTrackedSponge = _activeSponges.remove(key);
    if (removedByInternalWrite || removedTrackedSponge) {
      _scheduleAfterSpongeRemoval(world, x, y, z);
    }
  }

  void _scheduleAfterSpongeRemoval(VoxelWorld world, int x, int y, int z) {
    final reach = spongeRadius + 1;
    for (var dy = -reach; dy <= reach; dy++) {
      for (var dz = -reach; dz <= reach; dz++) {
        for (var dx = -reach; dx <= reach; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          final nz = z + dz;
          if (!VoxelWorld.inBounds(nx, ny, nz)) continue;
          final raw = world.blockAt(nx, ny, nz);
          final id = Blocks.id(raw);
          if (!LiquidState.isLiquidId(id)) continue;
          _scheduleLiquid(nx, ny, nz, id, _currentTick + _fluidDelay(id));
        }
      }
    }
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
      enqueue(x, y, z);
      assert(
        _hasGenericScheduled(key),
        'An active TNT fuse must stay scheduled.',
      );
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
    final oldRaw = builder.world.blockAt(x, y, z);
    if (!builder.set(x, y, z, raw)) return;
    _scheduleWorldCell(builder.world, x, y, z, previousRaw: oldRaw);
    for (final offset in _faceOffsets) {
      _scheduleWorldCell(
        builder.world,
        x + offset.$1,
        y + offset.$2,
        z + offset.$3,
      );
    }
  }

  void _scheduleWorldCell(
    VoxelWorld world,
    int x,
    int y,
    int z, {
    int? previousRaw,
  }) {
    if (!VoxelWorld.inBounds(x, y, z)) return;
    final raw = world.blockAt(x, y, z);
    final behavior = _behaviorForRaw(raw);
    _reconcileSpongeState(world, x, y, z, behavior, previousRaw: previousRaw);
    if (behavior == BlockBehavior.water || behavior == BlockBehavior.lava) {
      final id = Blocks.id(raw);
      _scheduleLiquid(x, y, z, id, _currentTick + _fluidDelay(id));
      return;
    }
    if (behavior == BlockBehavior.sponge) {
      if (_hasWaterNearby(world, x, y, z)) _scheduleGeneric(x, y, z);
      return;
    }
    if (behavior == BlockBehavior.falling) {
      _scheduleGeneric(x, y, z);
      return;
    }
    if (behavior == BlockBehavior.tnt &&
        _tntFuses.containsKey(worldPositionKey(x, y, z))) {
      _scheduleGeneric(x, y, z);
    }
  }

  bool _scheduleGeneric(int x, int y, int z) => _scheduleKey(
    worldPositionKey(x, y, z),
    expectedLiquidId: _genericIdentity,
    dueTick: _currentTick + 1,
  );

  bool _scheduleLiquid(int x, int y, int z, int liquidId, int dueTick) =>
      _scheduleKey(
        worldPositionKey(x, y, z),
        expectedLiquidId: liquidId,
        dueTick: dueTick,
      );

  bool _scheduleKey(
    int key, {
    required int expectedLiquidId,
    required int dueTick,
    bool markRetry = true,
  }) {
    final identity = _scheduleIdentity(key, expectedLiquidId);
    if (_scheduled.containsKey(identity)) return false;
    if (_scheduled.length >= maxQueue) {
      _droppedUpdates++;
      if (markRetry) _markRetryAroundKey(key);
      return false;
    }
    final normalizedDue = dueTick <= _currentTick ? _currentTick + 1 : dueTick;
    final entry = _ScheduledEntry(
      key: key,
      expectedLiquidId: expectedLiquidId,
      dueTick: normalizedDue,
      sequence: _nextSequence++,
    );
    _scheduled[identity] = entry;
    _heapPush(entry);
    return true;
  }

  bool _hasGenericScheduled(int key) =>
      _scheduled.containsKey(_scheduleIdentity(key, _genericIdentity));

  void _promoteRetries(VoxelWorld world) {
    if (_retryChunkCount == 0 || _scheduled.length >= maxQueue) return;
    var scannedChunks = 0;
    for (
      var chunkIndex = 0;
      chunkIndex < _worldChunkCount && scannedChunks < _retryChunksPerTick;
      chunkIndex++
    ) {
      if (!_isRetryMarked(chunkIndex)) continue;
      scannedChunks++;
      // Clear before scanning so overflow caused by reconciliation can re-mark
      // this same chunk without being erased at the end of the pass.
      _clearRetryChunk(chunkIndex);
      final chunk = world.chunks[chunkIndex];
      for (var localIndex = 0; localIndex < ChunkIndex.volume; localIndex++) {
        if (_scheduled.length >= maxQueue) {
          _markRetryChunk(chunkIndex);
          return;
        }
        final raw = chunk.blocks[localIndex];
        final behavior = _behaviorForRaw(raw);
        final (x, y, z) = _worldCoordinates(chunk, localIndex);
        _reconcileSpongeState(world, x, y, z, behavior);
        if (behavior == BlockBehavior.water || behavior == BlockBehavior.lava) {
          if (_needsFluidUpdate(world, x, y, z, raw)) {
            _scheduleKey(
              worldPositionKey(x, y, z),
              expectedLiquidId: Blocks.id(raw),
              dueTick: _currentTick + _fluidDelay(Blocks.id(raw)),
              markRetry: false,
            );
          }
        } else if (behavior == BlockBehavior.falling) {
          if (y > 0 && Blocks.id(world.blockAt(x, y - 1, z)) == Blocks.air) {
            _scheduleKey(
              worldPositionKey(x, y, z),
              expectedLiquidId: _genericIdentity,
              dueTick: _currentTick + 1,
              markRetry: false,
            );
          }
        } else if (behavior == BlockBehavior.sponge) {
          if (_hasWaterNearby(world, x, y, z)) {
            _scheduleKey(
              worldPositionKey(x, y, z),
              expectedLiquidId: _genericIdentity,
              dueTick: _currentTick + 1,
              markRetry: false,
            );
          }
        } else if (behavior == BlockBehavior.tnt &&
            _tntFuses.containsKey(worldPositionKey(x, y, z))) {
          _scheduleKey(
            worldPositionKey(x, y, z),
            expectedLiquidId: _genericIdentity,
            dueTick: _currentTick + 1,
            markRetry: false,
          );
        }
        if (_scheduled.length >= maxQueue &&
            localIndex + 1 < ChunkIndex.volume) {
          _markRetryChunk(chunkIndex);
          return;
        }
      }
    }
  }

  void _markRetryAroundKey(int key) {
    final (x, y, z) = _decodePosition(key);
    final cx = x >> 4;
    final cy = y >> 4;
    final cz = z >> 4;
    final lx = x & 15;
    final ly = y & 15;
    final lz = z & 15;
    final minCx = lx == 0 && cx > 0 ? cx - 1 : cx;
    final maxCx = lx == 15 && cx < WorldDims.worldChunksX - 1 ? cx + 1 : cx;
    final minCy = ly == 0 && cy > 0 ? cy - 1 : cy;
    final maxCy = ly == 15 && cy < WorldDims.worldChunksY - 1 ? cy + 1 : cy;
    final minCz = lz == 0 && cz > 0 ? cz - 1 : cz;
    final maxCz = lz == 15 && cz < WorldDims.worldChunksZ - 1 ? cz + 1 : cz;
    for (var retryCy = minCy; retryCy <= maxCy; retryCy++) {
      for (var retryCz = minCz; retryCz <= maxCz; retryCz++) {
        for (var retryCx = minCx; retryCx <= maxCx; retryCx++) {
          _markRetryChunk(VoxelWorld.chunkIndexOf(retryCx, retryCy, retryCz));
        }
      }
    }
  }

  void _markRetryChunk(int chunkIndex) {
    final word = chunkIndex ~/ _bitsPerRetryWord;
    final mask = 1 << (chunkIndex % _bitsPerRetryWord);
    if ((_retryWords[word] & mask) != 0) return;
    _retryWords[word] |= mask;
    _retryChunkCount++;
  }

  bool _isRetryMarked(int chunkIndex) {
    final word = chunkIndex ~/ _bitsPerRetryWord;
    final mask = 1 << (chunkIndex % _bitsPerRetryWord);
    return (_retryWords[word] & mask) != 0;
  }

  void _clearRetryChunk(int chunkIndex) {
    final word = chunkIndex ~/ _bitsPerRetryWord;
    final mask = 1 << (chunkIndex % _bitsPerRetryWord);
    if ((_retryWords[word] & mask) == 0) return;
    _retryWords[word] &= ~mask;
    _retryChunkCount--;
  }

  void _heapPush(_ScheduledEntry entry) {
    var index = _heap.length;
    _heap.add(entry);
    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (!_entryBefore(entry, _heap[parent])) break;
      _heap[index] = _heap[parent];
      index = parent;
    }
    _heap[index] = entry;
  }

  _ScheduledEntry? _peekScheduled() => _heap.isEmpty ? null : _heap.first;

  _ScheduledEntry? _popScheduled() {
    if (_heap.isEmpty) return null;
    final first = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isEmpty) return first;
    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      if (left >= _heap.length) break;
      final right = left + 1;
      var child = left;
      if (right < _heap.length && _entryBefore(_heap[right], _heap[left])) {
        child = right;
      }
      if (!_entryBefore(_heap[child], last)) break;
      _heap[index] = _heap[child];
      index = child;
    }
    _heap[index] = last;
    return first;
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
