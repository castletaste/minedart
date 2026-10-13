import 'package:minedart_core/minedart_core.dart';

/// Same rule as minedart's `defaultWorldSpawn`.
({double x, double y, double z}) defaultSpawn(VoxelWorld world) {
  final centerX = WorldDims.worldBlocksX ~/ 2;
  final centerZ = WorldDims.worldBlocksZ ~/ 2;
  var bestX = centerX;
  var bestZ = centerZ;
  var bestY = world.skyHeight[centerX + centerZ * WorldDims.worldBlocksX];
  var bestDistance = 1 << 30;
  for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
    for (var x = 0; x < WorldDims.worldBlocksX; x++) {
      final height = world.skyHeight[x + z * WorldDims.worldBlocksX];
      if (height <= 1 || height + 1 >= WorldDims.worldBlocksY) continue;
      final topId = Blocks.id(world.blockAt(x, height - 1, z));
      final definition = topId < blockDefs.length ? blockDefs[topId] : null;
      if (definition == null ||
          !definition.solid ||
          topId == Blocks.bedrock ||
          topId == Blocks.logOak ||
          topId == Blocks.leavesOak) {
        continue;
      }
      final dx = x - centerX;
      final dz = z - centerZ;
      final distance = dx * dx + dz * dz;
      if (distance < bestDistance ||
          (distance == bestDistance && height > bestY)) {
        bestX = x;
        bestZ = z;
        bestY = height;
        bestDistance = distance;
      }
    }
  }
  return (x: bestX + 0.5, y: bestY.toDouble(), z: bestZ + 0.5);
}
