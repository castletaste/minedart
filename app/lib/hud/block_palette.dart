/// HUD palette: hotbar contents and flat swatch colors per block.
///
/// Colors approximate the generated atlas tiles (see bin/make_atlas.dart);
/// the HUD draws flat squares instead of rendering 3D previews.
library;

import 'dart:ui' show Color;

import 'package:minedart_core/minedart_core.dart';

/// The nine hotbar slots, in order.
const List<int> kHotbarBlocks = <int>[
  Blocks.stone,
  Blocks.dirt,
  Blocks.grass,
  Blocks.planksOak,
  Blocks.cobblestone,
  Blocks.sand,
  Blocks.logOak,
  Blocks.leavesOak,
  Blocks.tnt,
];

/// Flat swatch color per block id, sampled from the atlas generator.
const Map<int, Color> kBlockColors = <int, Color>{
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
};

/// Swatch color for [blockId], falling back to neutral gray.
Color blockColor(int blockId) =>
    kBlockColors[blockId] ?? const Color(0xFF9E9E9E);

/// Human-readable label for [blockId] ('stone', 'planks oak', ...).
String blockLabel(int blockId) {
  if (blockId <= Blocks.air || blockId >= blockDefs.length) return 'air';
  final definition = blockDefs[blockId];
  if (definition == null) return 'air';
  return definition.name.replaceAll('_', ' ');
}
