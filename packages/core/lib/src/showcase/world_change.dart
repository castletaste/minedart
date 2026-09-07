library;

import '../world.dart';
import '../chunk.dart';

/// One raw voxel mutation. Coordinates and both Uint16 values are retained so
/// the mutation can be replayed in either direction without consulting a save.
final class WorldChange {
  const WorldChange({
    required this.x,
    required this.y,
    required this.z,
    required this.oldRaw,
    required this.newRaw,
  });

  final int x;
  final int y;
  final int z;
  final int oldRaw;
  final int newRaw;

  WorldChange get inverted =>
      WorldChange(x: x, y: y, z: z, oldRaw: newRaw, newRaw: oldRaw);
}

/// An atomic edit/simulation group and the chunks requiring a remesh.
final class WorldChangeSet {
  WorldChangeSet._(List<WorldChange> changes, Set<int> dirtyChunks)
    : changes = List.unmodifiable(changes),
      dirtyChunks = Set.unmodifiable(dirtyChunks);

  factory WorldChangeSet.empty() => WorldChangeSet._(const [], const {});

  /// Merges change sets into one deterministic undo group.
  ///
  /// A coordinate keeps the first [WorldChange.oldRaw] observed and the last
  /// [WorldChange.newRaw] observed. Coordinates retain their first-seen order,
  /// net-zero changes are omitted, and dirty chunks are unioned even when all
  /// voxel changes cancel out.
  factory WorldChangeSet.merge(Iterable<WorldChangeSet> changeSets) {
    final order = <(int, int, int)>[];
    final changes = <(int, int, int), WorldChange>{};
    final dirtyChunks = <int>{};

    for (final changeSet in changeSets) {
      dirtyChunks.addAll(changeSet.dirtyChunks);
      for (final change in changeSet.changes) {
        final coordinate = (change.x, change.y, change.z);
        final first = changes[coordinate];
        if (first == null) {
          order.add(coordinate);
          changes[coordinate] = change;
        } else {
          changes[coordinate] = WorldChange(
            x: first.x,
            y: first.y,
            z: first.z,
            oldRaw: first.oldRaw,
            newRaw: change.newRaw,
          );
        }
      }
    }

    return WorldChangeSet._([
      for (final coordinate in order)
        if (changes[coordinate] case final change?)
          if (change.oldRaw != change.newRaw) change,
    ], dirtyChunks);
  }

  final List<WorldChange> changes;
  final Set<int> dirtyChunks;

  bool get isEmpty => changes.isEmpty;
  bool get isNotEmpty => changes.isNotEmpty;

  WorldChangeSet get inverted => WorldChangeSet._([
    for (final change in changes.reversed) change.inverted,
  ], dirtyChunks);

  /// Applies this group in its declared direction and reports actual dirty
  /// chunks from [VoxelWorld]. The returned values reflect the world at apply
  /// time, which also makes replay robust after loading a compatible world.
  WorldChangeSet applyTo(VoxelWorld world) {
    final builder = WorldChangeSetBuilder(world);
    for (final change in changes) {
      builder.set(change.x, change.y, change.z, change.newRaw);
    }
    return builder.build();
  }
}

/// Coalesces repeated writes to one coordinate into one old/new pair.
final class WorldChangeSetBuilder {
  WorldChangeSetBuilder(this.world);

  final VoxelWorld world;
  final List<int> _order = [];
  final Map<int, WorldChange> _changes = {};
  final Set<int> _dirtyChunks = {};

  bool set(int x, int y, int z, int newRaw) {
    if (!VoxelWorld.inBounds(x, y, z)) return false;
    final oldRaw = world.blockAt(x, y, z);
    if (oldRaw == newRaw) return false;

    // Mutate first so a rejected raw value cannot partially alter this
    // builder's ordering/change bookkeeping.
    final dirty = world.setBlock(x, y, z, newRaw);

    final key = worldPositionKey(x, y, z);
    final first = _changes[key];
    if (first == null) {
      _order.add(key);
      _changes[key] = WorldChange(
        x: x,
        y: y,
        z: z,
        oldRaw: oldRaw,
        newRaw: newRaw,
      );
    } else {
      _changes[key] = WorldChange(
        x: x,
        y: y,
        z: z,
        oldRaw: first.oldRaw,
        newRaw: newRaw,
      );
    }
    _dirtyChunks.addAll(dirty);
    return true;
  }

  WorldChangeSet build() => WorldChangeSet._([
    for (final key in _order)
      if (_changes[key] case final change?)
        if (change.oldRaw != change.newRaw) change,
  ], _dirtyChunks);
}

/// Stable finite-world coordinate key shared by history and tick queues.
int worldPositionKey(int x, int y, int z) =>
    x +
    z * WorldDims.worldBlocksX +
    y * WorldDims.worldBlocksX * WorldDims.worldBlocksZ;
