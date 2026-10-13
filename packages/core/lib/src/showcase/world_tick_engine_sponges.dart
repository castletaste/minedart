part of 'world_tick_engine.dart';

extension on WorldTickEngine {
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
          if (WorldTickEngine._behaviorAt(world, nx, ny, nz) ==
              BlockBehavior.water) {
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
          if (WorldTickEngine._behaviorAt(world, x + dx, y + dy, z + dz) ==
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
        if (WorldTickEngine._behaviorForRaw(chunk.blocks[localIndex]) !=
            BlockBehavior.sponge) {
          continue;
        }
        final (x, y, z) = WorldTickEngine._worldCoordinates(chunk, localIndex);
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
        WorldTickEngine._behaviorForRaw(previousRaw) == BlockBehavior.sponge;
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
          _scheduleLiquid(
            nx,
            ny,
            nz,
            id,
            _currentTick + WorldTickEngine._fluidDelay(id),
          );
        }
      }
    }
  }
}
