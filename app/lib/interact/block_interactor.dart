/// Break/place block interaction built on the core DDA voxel raycast.
///
/// The logic here is deliberately Flutter-free so it can be unit tested
/// without a widget binding. Hot paths reuse scratch objects: a single
/// [Aabb] and no per-call vector allocation beyond what the raycast needs.
library;

import 'package:minedart_core/minedart_core.dart';
import 'package:vector_math/vector_math.dart';

/// What an edit attempt actually did.
enum BlockEditKind { none, broke, placed }

/// Result of a break/place attempt.
final class BlockEditResult {
  const BlockEditResult({
    required this.kind,
    required this.x,
    required this.y,
    required this.z,
    required this.blockId,
    this.changeSet,
  });

  static const BlockEditResult none = BlockEditResult(
    kind: BlockEditKind.none,
    x: 0,
    y: 0,
    z: 0,
    blockId: Blocks.air,
  );

  final BlockEditKind kind;
  final int x;
  final int y;
  final int z;

  /// Block id after the edit (air for a break).
  final int blockId;
  final WorldChangeSet? changeSet;

  bool get changed => kind != BlockEditKind.none;
}

/// Default reach in blocks, matching Minecraft Classic-ish survival reach.
const double kDefaultReach = 5;

/// True when a placement may overwrite the block currently in a cell.
bool isReplaceable(int raw) {
  final id = Blocks.id(raw);
  return id == Blocks.air || id == Blocks.water || id == Blocks.lava;
}

/// Fills [out] with the player collision box derived from an eye position.
///
/// The camera eye is the only player state this layer is allowed to read
/// (physics/camera ownership lives elsewhere), so the body is reconstructed
/// from [PlayerBody] constants.
void writePlayerAabbFromEye(Vector3 eye, Aabb out) {
  final feetY = eye.y - PlayerBody.eyeHeight;
  out.setValues(
    eye.x - PlayerBody.halfWidth,
    feetY,
    eye.z - PlayerBody.halfWidth,
    eye.x + PlayerBody.halfWidth,
    feetY + PlayerBody.height,
    eye.z + PlayerBody.halfWidth,
  );
}

/// Whether [blockId] can be placed at (x,y,z) without clipping the player.
bool canPlaceBlock(
  VoxelWorld world,
  int x,
  int y,
  int z,
  int blockId,
  Aabb playerAabb,
) {
  if (blockId <= Blocks.air || blockId >= blockDefs.length) return false;
  final definition = blockDefs[blockId];
  if (definition == null) return false;
  if (!VoxelWorld.inBounds(x, y, z)) return false;
  if (!isReplaceable(world.blockAt(x, y, z))) return false;
  if (definition.solid && playerAabb.intersectsVoxel(x, y, z)) return false;
  return true;
}

/// Whether the block currently at (x,y,z) can be removed.
bool canBreakBlock(VoxelWorld world, int x, int y, int z) {
  final definition = blockDefs[Blocks.id(world.blockAt(x, y, z))];
  return definition != null && definition.breakable;
}

/// Applies break/place edits to a [VoxelWorld] and reports dirty chunks.
final class BlockInteractor {
  BlockInteractor({
    required this.world,
    required this.onDirty,
    this.reach = kDefaultReach,
  });

  final VoxelWorld world;

  /// Called with the chunk indices whose meshes need rebuilding.
  final void Function(Set<int> dirtyChunks) onDirty;

  final double reach;

  final Aabb _playerBox = Aabb();

  /// The block currently under the crosshair, if any.
  VoxelRayHit? target(Vector3 eye, Vector3 forward) =>
      raycastVoxel(world, eye, forward, maxDistance: reach);

  /// Removes the targeted block (left click).
  BlockEditResult breakBlock(Vector3 eye, Vector3 forward) {
    final hit = target(eye, forward);
    if (hit == null) return BlockEditResult.none;
    if (!canBreakBlock(world, hit.x, hit.y, hit.z)) return BlockEditResult.none;
    final builder = WorldChangeSetBuilder(world)
      ..set(hit.x, hit.y, hit.z, Blocks.air);
    final changes = builder.build();
    if (changes.isEmpty) return BlockEditResult.none;
    onDirty(changes.dirtyChunks);
    return BlockEditResult(
      kind: BlockEditKind.broke,
      x: hit.x,
      y: hit.y,
      z: hit.z,
      blockId: Blocks.air,
      changeSet: changes,
    );
  }

  /// Places [blockId] against the targeted face (right click).
  BlockEditResult placeBlock(Vector3 eye, Vector3 forward, int blockId) {
    final hit = target(eye, forward);
    if (hit == null) return BlockEditResult.none;
    final x = hit.previousX;
    final y = hit.previousY;
    final z = hit.previousZ;
    writePlayerAabbFromEye(eye, _playerBox);
    if (!canPlaceBlock(world, x, y, z, blockId, _playerBox)) {
      return BlockEditResult.none;
    }
    final builder = WorldChangeSetBuilder(world)
      ..set(x, y, z, Blocks.pack(blockId));
    final changes = builder.build();
    if (changes.isEmpty) return BlockEditResult.none;
    onDirty(changes.dirtyChunks);
    return BlockEditResult(
      kind: BlockEditKind.placed,
      x: x,
      y: y,
      z: z,
      blockId: blockId,
      changeSet: changes,
    );
  }
}
