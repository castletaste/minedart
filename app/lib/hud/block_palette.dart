/// HUD palette: hotbar contents and flat swatch colors per block.
///
/// The HUD draws flat squares instead of rendering 3D previews. Swatches track
/// the atlas selected by `MINEDART_ATLAS`.
library;

import 'dart:ui' show Color;

import 'package:minedart_core/minedart_core.dart';

import '../assets/atlas_selection.dart';

/// The nine hotbar slots, in order.
const List<int> kHotbarBlocks = <int>[
  Blocks.tnt,
  Blocks.stone,
  Blocks.dirt,
  Blocks.grass,
  Blocks.planksOak,
  Blocks.cobblestone,
  Blocks.sand,
  Blocks.logOak,
  Blocks.leavesOak,
];

/// Exact flat swatches used with the immutable legacy atlas.
const Map<int, Color> kLegacyBlockColors = <int, Color>{
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

/// Flat swatches generated from the completed Alpha-like atlas masters.
///
/// Each opaque RGB value is the integer-half-up, alpha-weighted mean of the
/// representative 16x16 master. Grass uses its top master; logs and TNT use
/// their side masters. Tests recalculate these constants from the master PNGs.
const Map<int, Color> kAlphaBlockColors = <int, Color>{
  Blocks.stone: Color(0xFF79787A),
  Blocks.dirt: Color(0xFF774C2F),
  Blocks.grass: Color(0xFF529735),
  Blocks.sand: Color(0xFFCBB98E),
  Blocks.gravel: Color(0xFF7C6D6D),
  Blocks.logOak: Color(0xFF48351D),
  Blocks.leavesOak: Color(0xFF35711D),
  Blocks.water: Color(0xFF1137AC),
  Blocks.bedrock: Color(0xFF383634),
  Blocks.oreCoal: Color(0xFF6E6D6F),
  Blocks.oreIron: Color(0xFF7C7674),
  Blocks.oreGold: Color(0xFF7F7A70),
  Blocks.planksOak: Color(0xFF8A6E45),
  Blocks.cobblestone: Color(0xFF6D6C6B),
  Blocks.glass: Color(0xFFD3DBDD),
  Blocks.brick: Color(0xFF8E4D41),
  Blocks.sponge: Color(0xFFCEAB2A),
  Blocks.flowerDandelion: Color(0xFF9AA42D),
  Blocks.flowerRose: Color(0xFF6F572C),
  Blocks.mushroomBrown: Color(0xFF916942),
  Blocks.mushroomRed: Color(0xFFB74739),
  Blocks.lava: Color(0xFFD73B05),
  Blocks.tnt: Color(0xFF9D493C),
  Blocks.sapling: Color(0xFF53682D),
  Blocks.goldBlock: Color(0xFFD8A82D),
  Blocks.ironBlock: Color(0xFFADB4B7),
  Blocks.clothWhite: Color(0xFFDFDBCD),
  Blocks.clothRed: Color(0xFFAD3533),
  Blocks.clothOrange: Color(0xFFCF6B2A),
  Blocks.clothYellow: Color(0xFFDABB34),
  Blocks.clothLime: Color(0xFF5FA037),
  Blocks.clothBlue: Color(0xFF365EA9),
  Blocks.obsidian: Color(0xFF292235),
};

/// Pure palette lookup for a validated atlas variant.
Map<int, Color> blockColorsFor(AtlasVariant variant) => switch (variant) {
  AtlasVariant.alpha => kAlphaBlockColors,
  AtlasVariant.legacy => kLegacyBlockColors,
};

/// Flat swatches for the compile-time selected atlas.
final Map<int, Color> kBlockColors = blockColorsFor(selectedAtlas.variant);

/// Swatch color for [blockId], falling back to neutral gray.
Color blockColor(int blockId, {AtlasVariant? variant}) =>
    (variant == null ? kBlockColors : blockColorsFor(variant))[blockId] ??
    const Color(0xFF9E9E9E);

/// Human-readable label for [blockId] ('stone', 'planks oak', ...).
String blockLabel(int blockId) {
  if (blockId <= Blocks.air || blockId >= blockDefs.length) return 'air';
  final definition = blockDefs[blockId];
  if (definition == null) return 'air';
  return definition.name.replaceAll('_', ' ');
}
