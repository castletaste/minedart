part of 'world_tick_engine.dart';

extension on WorldTickEngine {
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
    final dueTick = _currentTick + WorldTickEngine._fluidDelay(id) - 1;
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
          !WorldTickEngine._lavaLevelAdvanceAllowed(
            world.seed,
            x,
            y,
            z,
            _currentTick,
          )) {
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

    final nextLevel = falling ? 1 : level + WorldTickEngine._fluidDecay(id);
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
          : neighborMetadata + WorldTickEngine._fluidDecay(fluidId);
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
    if (WorldTickEngine._behaviorForRaw(target) == BlockBehavior.plant) {
      return true;
    }
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
    final behavior = WorldTickEngine._behaviorForRaw(raw);
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
        : (metadata & LiquidState.levelMask) + WorldTickEngine._fluidDecay(id);
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
}
