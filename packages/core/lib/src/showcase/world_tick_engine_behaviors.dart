part of 'world_tick_engine.dart';

extension on WorldTickEngine {
  void _processEntry(
    VoxelWorld world,
    WorldChangeSetBuilder builder,
    _ScheduledEntry entry,
  ) {
    final (x, y, z) = WorldTickEngine._decodePosition(entry.key);
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
}

extension on WorldTickEngine {
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
}
