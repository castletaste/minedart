import 'package:minedart_core/minedart_core.dart';

import 'launch_config.dart';

/// Generates the finite showcase worlds represented in portable seed links.
VoxelWorld generatePresetWorld(int seed, LaunchWorldPreset preset) {
  final world = VoxelWorld()..seed = seed;
  switch (preset) {
    case LaunchWorldPreset.classic:
      WorldGenerator(seed).generate(world);
    case LaunchWorldPreset.flat:
      _generateFlat(world);
    case LaunchWorldPreset.islands:
      IslandsWorldGenerator(seed).generate(world);
  }
  return world;
}

String sharedWorldId(int seed, LaunchWorldPreset preset, {required int nonce}) {
  final encodedSeed = seed < 0
      ? 'n${(-seed).toRadixString(16)}'
      : seed.toRadixString(16);
  return 'shared-${preset.name}-$encodedSeed-${nonce.toRadixString(36)}';
}

String duplicateWorldId({
  required String sourceId,
  required int seed,
  required int nonce,
}) {
  final preset = presetForWorldId(sourceId);
  return preset == LaunchWorldPreset.classic
      ? 'world-${nonce.toRadixString(36)}'
      : sharedWorldId(seed, preset, nonce: nonce);
}

LaunchWorldPreset presetForWorldId(String id) {
  for (final preset in LaunchWorldPreset.values) {
    if (id.startsWith('shared-${preset.name}-')) return preset;
  }
  return LaunchWorldPreset.classic;
}

void _generateFlat(VoxelWorld world) {
  for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
    for (var x = 0; x < WorldDims.worldBlocksX; x++) {
      _setFast(world, x, 0, z, Blocks.bedrock);
      for (var y = 1; y < 26; y++) {
        _setFast(world, x, y, z, Blocks.stone);
      }
      for (var y = 26; y < 29; y++) {
        _setFast(world, x, y, z, Blocks.dirt);
      }
      _setFast(world, x, 29, z, Blocks.grass);
    }
  }
  world.recomputeSkylight();
}

void _setFast(VoxelWorld world, int x, int y, int z, int raw) {
  world.chunkAt(x >> 4, y >> 4, z >> 4).set(x & 15, y & 15, z & 15, raw);
}
