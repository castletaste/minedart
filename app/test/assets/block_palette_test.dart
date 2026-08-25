import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:minedart/assets/atlas_selection.dart';
import 'package:minedart/hud/block_palette.dart';
import 'package:minedart_core/minedart_core.dart';

const Map<int, Color> _expectedLegacyColors = <int, Color>{
  Blocks.stone: Color(0xFF7D7D7D),
  Blocks.dirt: Color(0xFF80512E),
  Blocks.grass: Color(0xFF549A39),
  Blocks.sand: Color(0xFFE2C879),
  Blocks.gravel: Color(0xFF77746D),
  Blocks.logOak: Color(0xFF7D522A),
  Blocks.leavesOak: Color(0xFF286527),
  Blocks.water: Color(0xFF2A70C9),
  Blocks.bedrock: Color(0xFF373737),
  Blocks.oreCoal: Color(0xFF6A6A6A),
  Blocks.oreIron: Color(0xFF9A8B78),
  Blocks.oreGold: Color(0xFFAE9A55),
  Blocks.planksOak: Color(0xFFA46B35),
  Blocks.cobblestone: Color(0xFF666666),
  Blocks.glass: Color(0xFFABE8FF),
  Blocks.brick: Color(0xFFA94530),
  Blocks.sponge: Color(0xFFE6CF39),
  Blocks.flowerDandelion: Color(0xFFFFE542),
  Blocks.flowerRose: Color(0xFFE8494F),
  Blocks.mushroomBrown: Color(0xFFA4774A),
  Blocks.mushroomRed: Color(0xFFD83B3B),
  Blocks.lava: Color(0xFFE05A18),
  Blocks.tnt: Color(0xFFB52F2F),
  Blocks.sapling: Color(0xFF308433),
  Blocks.goldBlock: Color(0xFFF0C83B),
  Blocks.ironBlock: Color(0xFFD8D8D8),
  Blocks.clothWhite: Color(0xFFE5E5E5),
  Blocks.clothRed: Color(0xFFC83B3B),
  Blocks.clothOrange: Color(0xFFDB762E),
  Blocks.clothYellow: Color(0xFFE5CF42),
  Blocks.clothLime: Color(0xFF74B83D),
  Blocks.clothBlue: Color(0xFF395FAF),
  Blocks.obsidian: Color(0xFF271F36),
};

const Map<int, String> _alphaMasterForBlock = <int, String>{
  Blocks.stone: '00-stone.png',
  Blocks.dirt: '01-dirt.png',
  Blocks.grass: '02-grass-top.png',
  Blocks.sand: '04-sand.png',
  Blocks.gravel: '05-gravel.png',
  Blocks.logOak: '06-log-side.png',
  Blocks.leavesOak: '08-leaves.png',
  Blocks.water: '09-water.png',
  Blocks.bedrock: '10-bedrock.png',
  Blocks.oreCoal: '11-ore-coal.png',
  Blocks.oreIron: '12-ore-iron.png',
  Blocks.oreGold: '13-ore-gold.png',
  Blocks.planksOak: '14-planks.png',
  Blocks.cobblestone: '15-cobblestone.png',
  Blocks.glass: '16-glass.png',
  Blocks.brick: '17-brick.png',
  Blocks.sponge: '18-sponge.png',
  Blocks.flowerDandelion: '19-flower-dandelion.png',
  Blocks.flowerRose: '20-flower-rose.png',
  Blocks.mushroomBrown: '21-mushroom-brown.png',
  Blocks.mushroomRed: '22-mushroom-red.png',
  Blocks.lava: '23-lava.png',
  Blocks.tnt: '24-tnt-side.png',
  Blocks.sapling: '27-sapling.png',
  Blocks.goldBlock: '28-gold-block.png',
  Blocks.ironBlock: '29-iron-block.png',
  Blocks.clothWhite: '30-cloth-white.png',
  Blocks.clothRed: '31-cloth-red.png',
  Blocks.clothOrange: '32-cloth-orange.png',
  Blocks.clothYellow: '33-cloth-yellow.png',
  Blocks.clothLime: '34-cloth-lime.png',
  Blocks.clothBlue: '35-cloth-blue.png',
  Blocks.obsidian: '36-obsidian.png',
};

void main() {
  test('selected palette follows the compile-time atlas', () {
    expect(kBlockColors, same(blockColorsFor(selectedAtlas.variant)));
  });

  test('legacy palette remains exactly compatible', () {
    expect(kLegacyBlockColors, _expectedLegacyColors);
    expect(blockColorsFor(AtlasVariant.legacy), same(kLegacyBlockColors));
    for (final entry in _expectedLegacyColors.entries) {
      expect(blockColor(entry.key, variant: AtlasVariant.legacy), entry.value);
    }
  });

  test('legacy obsidian swatch is the additive tile mean', () {
    final atlas = img.decodePng(
      File('assets/textures/atlas.png').readAsBytesSync(),
    );
    expect(atlas, isNotNull);
    expect(
      kLegacyBlockColors[Blocks.obsidian],
      _alphaWeightedMeanRegion(atlas!, 64, 32, 16, 16),
    );
  });

  test('Alpha-like swatches are deterministic master means', () {
    for (final entry in _alphaMasterForBlock.entries) {
      final path = 'tool/atlas_sources/default_alpha/masters/${entry.value}';
      final image = img.decodePng(File(path).readAsBytesSync());
      expect(image, isNotNull, reason: '$path must decode as PNG');
      expect(image!.width, 16, reason: path);
      expect(image.height, 16, reason: path);
      expect(
        kAlphaBlockColors[entry.key],
        _alphaWeightedMean(image),
        reason: path,
      );
    }
  });

  test('both atlas variants cover every real block', () {
    final blockIds = <int>{
      for (var id = 1; id < blockDefs.length; id++)
        if (blockDefs[id] != null) id,
    };
    expect(_alphaMasterForBlock.keys.toSet(), blockIds);
    expect(kAlphaBlockColors.keys.toSet(), blockIds);
    expect(kLegacyBlockColors.keys.toSet(), blockIds);

    for (final variant in AtlasVariant.values) {
      final colors = blockColorsFor(variant);
      for (final blockId in blockIds) {
        expect(colors[blockId], isNotNull, reason: '$variant block $blockId');
      }
    }
  });
}

Color _alphaWeightedMean(img.Image image) {
  return _alphaWeightedMeanRegion(image, 0, 0, image.width, image.height);
}

Color _alphaWeightedMeanRegion(
  img.Image image,
  int originX,
  int originY,
  int width,
  int height,
) {
  var alphaTotal = 0;
  var redTotal = 0;
  var greenTotal = 0;
  var blueTotal = 0;
  for (var y = originY; y < originY + height; y++) {
    for (var x = originX; x < originX + width; x++) {
      final pixel = image.getPixel(x, y);
      final alpha = pixel.a.toInt();
      alphaTotal += alpha;
      redTotal += pixel.r.toInt() * alpha;
      greenTotal += pixel.g.toInt() * alpha;
      blueTotal += pixel.b.toInt() * alpha;
    }
  }
  if (alphaTotal == 0) {
    throw StateError('Cannot derive a swatch from a transparent master.');
  }
  int rounded(int total) => (total + alphaTotal ~/ 2) ~/ alphaTotal;
  return Color.fromARGB(
    255,
    rounded(redTotal),
    rounded(greenTotal),
    rounded(blueTotal),
  );
}
