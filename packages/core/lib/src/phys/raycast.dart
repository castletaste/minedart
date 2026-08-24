/// Allocation-light Amanatides-Woo voxel traversal.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../block.dart';
import '../world.dart';

typedef RaycastPredicate = bool Function(int rawBlock, BlockDef definition);

bool defaultRaycastPredicate(int rawBlock, BlockDef definition) =>
    definition.solid || definition.breakable;

final class VoxelRayHit {
  const VoxelRayHit({
    required this.x,
    required this.y,
    required this.z,
    required this.rawBlock,
    required this.normalX,
    required this.normalY,
    required this.normalZ,
    required this.previousX,
    required this.previousY,
    required this.previousZ,
    required this.distance,
  });

  final int x;
  final int y;
  final int z;
  final int rawBlock;
  final int normalX;
  final int normalY;
  final int normalZ;
  final int previousX;
  final int previousY;
  final int previousZ;
  final double distance;
}

typedef RaycastHit = VoxelRayHit;

/// Casts from [origin] along [direction], which need not be normalized.
///
/// The default predicate ignores air and water, includes solid blocks, and
/// also includes non-solid breakable crosses such as flowers and mushrooms.
VoxelRayHit? raycastVoxel(
  VoxelWorld world,
  Vector3 origin,
  Vector3 direction, {
  double maxDistance = 5,
  RaycastPredicate predicate = defaultRaycastPredicate,
}) {
  if (!maxDistance.isFinite || maxDistance < 0) return null;
  final directionLength = math.sqrt(
    direction.x * direction.x +
        direction.y * direction.y +
        direction.z * direction.z,
  );
  if (directionLength == 0 || !directionLength.isFinite) return null;

  final dx = direction.x / directionLength;
  final dy = direction.y / directionLength;
  final dz = direction.z / directionLength;
  var x = origin.x.floor();
  var y = origin.y.floor();
  var z = origin.z.floor();
  var previousX = x;
  var previousY = y;
  var previousZ = z;
  var normalX = 0;
  var normalY = 0;
  var normalZ = 0;
  var distance = 0.0;

  final stepX = dx > 0 ? 1 : (dx < 0 ? -1 : 0);
  final stepY = dy > 0 ? 1 : (dy < 0 ? -1 : 0);
  final stepZ = dz > 0 ? 1 : (dz < 0 ? -1 : 0);
  final deltaX = stepX == 0 ? double.infinity : (1 / dx).abs();
  final deltaY = stepY == 0 ? double.infinity : (1 / dy).abs();
  final deltaZ = stepZ == 0 ? double.infinity : (1 / dz).abs();
  var nextX = stepX > 0
      ? (x + 1 - origin.x) / dx
      : (stepX < 0 ? (origin.x - x) / -dx : double.infinity);
  var nextY = stepY > 0
      ? (y + 1 - origin.y) / dy
      : (stepY < 0 ? (origin.y - y) / -dy : double.infinity);
  var nextZ = stepZ > 0
      ? (z + 1 - origin.z) / dz
      : (stepZ < 0 ? (origin.z - z) / -dz : double.infinity);

  while (distance <= maxDistance) {
    final raw = world.blockAt(x, y, z);
    final id = Blocks.id(raw);
    if (id > Blocks.air && id < blockDefs.length) {
      final definition = blockDefs[id];
      if (definition != null && predicate(raw, definition)) {
        return VoxelRayHit(
          x: x,
          y: y,
          z: z,
          rawBlock: raw,
          normalX: normalX,
          normalY: normalY,
          normalZ: normalZ,
          previousX: previousX,
          previousY: previousY,
          previousZ: previousZ,
          distance: distance,
        );
      }
    }

    previousX = x;
    previousY = y;
    previousZ = z;
    normalX = 0;
    normalY = 0;
    normalZ = 0;
    if (nextX <= nextY && nextX <= nextZ) {
      distance = nextX;
      if (distance > maxDistance) break;
      x += stepX;
      nextX += deltaX;
      normalX = -stepX;
    } else if (nextY <= nextZ) {
      distance = nextY;
      if (distance > maxDistance) break;
      y += stepY;
      nextY += deltaY;
      normalY = -stepY;
    } else {
      distance = nextZ;
      if (distance > maxDistance) break;
      z += stepZ;
      nextZ += deltaZ;
      normalZ = -stepZ;
    }
  }
  return null;
}

VoxelRayHit? raycast(
  VoxelWorld world,
  Vector3 origin,
  Vector3 direction, {
  double maxDistance = 5,
  RaycastPredicate predicate = defaultRaycastPredicate,
}) => raycastVoxel(
  world,
  origin,
  direction,
  maxDistance: maxDistance,
  predicate: predicate,
);
