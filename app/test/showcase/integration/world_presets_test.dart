import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/integration/launch_config.dart';
import 'package:minedart/showcase/integration/world_presets.dart';
import 'package:minedart/showcase/integration/showcase_app.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  test('flat preset builds the promised deterministic layers', () {
    final world = generatePresetWorld(42, LaunchWorldPreset.flat);
    expect(world.seed, 42);
    expect(Blocks.id(world.blockAt(10, 0, 10)), Blocks.bedrock);
    expect(Blocks.id(world.blockAt(10, 20, 10)), Blocks.stone);
    expect(Blocks.id(world.blockAt(10, 27, 10)), Blocks.dirt);
    expect(Blocks.id(world.blockAt(10, 29, 10)), Blocks.grass);
    expect(Blocks.id(world.blockAt(10, 30, 10)), Blocks.air);
    expect(world.skyHeight[10 + 10 * WorldDims.worldBlocksX], 30);
  });

  test('islands preset contains both ocean and raised land', () {
    final world = generatePresetWorld(0x5eed, LaunchWorldPreset.islands);
    var waterColumns = 0;
    var landColumns = 0;
    for (var z = 0; z < WorldDims.worldBlocksZ; z += 8) {
      for (var x = 0; x < WorldDims.worldBlocksX; x += 8) {
        if (Blocks.id(world.blockAt(x, 12, z)) == Blocks.water) {
          waterColumns++;
        }
        final height = world.skyHeight[x + z * WorldDims.worldBlocksX];
        if (height > 25) landColumns++;
      }
    }
    expect(waterColumns, greaterThan(0));
    expect(landColumns, greaterThan(0));
  });

  test('shared ids are stable and preserve the preset', () {
    expect(
      sharedWorldId(-42, LaunchWorldPreset.flat, nonce: 35),
      'shared-flat-n2a-z',
    );
    expect(presetForWorldId('shared-islands-5eed'), LaunchWorldPreset.islands);
    expect(presetForWorldId('world-local'), LaunchWorldPreset.classic);
    expect(
      presetForWorldId(
        duplicateWorldId(sourceId: 'shared-flat-2a-z', seed: 42, nonce: 36),
      ),
      LaunchWorldPreset.flat,
    );
  });

  test('empty MDRT filename receives a visible fallback name', () {
    expect(importedWorldName('.mdrt'), 'Imported Classic World');
    expect(importedWorldName('  .MDRT'), 'Imported Classic World');
    expect(importedWorldName('My World.mdrt'), 'My World');
  });
}
