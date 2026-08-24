/// Block ids and properties. Uint16 layout: bits 0-11 id, bits 12-15 metadata.
library;

abstract final class Blocks {
  static const int air = 0;
  static const int stone = 1;
  static const int dirt = 2;
  static const int grass = 3;
  static const int sand = 4;
  static const int gravel = 5;
  static const int logOak = 6;
  static const int leavesOak = 7;
  static const int water = 8;
  static const int bedrock = 9;
  static const int oreCoal = 10;
  static const int oreIron = 11;
  static const int oreGold = 12;
  static const int planksOak = 13;
  static const int cobblestone = 14;
  static const int glass = 15;
  static const int brick = 16;
  static const int sponge = 17;
  static const int flowerDandelion = 18;
  static const int flowerRose = 19;
  static const int mushroomBrown = 20;
  static const int mushroomRed = 21;
  static const int lava = 22;
  static const int tnt = 23;
  static const int sapling = 24;
  static const int goldBlock = 25;
  static const int ironBlock = 26;
  static const int clothWhite = 27;
  static const int clothRed = 28;
  static const int clothOrange = 29;
  static const int clothYellow = 30;
  static const int clothLime = 31;
  static const int clothBlue = 32;

  /// Exclusive upper bound for valid block ids, including air.
  static const int count = 33;

  static int id(int raw) => raw & 0x0FFF;
  static int meta(int raw) => (raw >> 12) & 0xF;
  static int pack(int id, [int meta = 0]) =>
      (id & 0x0FFF) | ((meta & 0xF) << 12);
}

/// Face indices used across meshing and AO.
abstract final class Face {
  static const int posX = 0; // east
  static const int negX = 1; // west
  static const int posY = 2; // up
  static const int negY = 3; // down
  static const int posZ = 4; // south
  static const int negZ = 5; // north
}

/// Simulation behavior owned by a block definition.
enum BlockBehavior { plain, falling, water, lava, sponge, tnt, plant }

final class BlockDef {
  const BlockDef({
    required this.name,
    this.opaque = true,
    bool? blocksLight,
    this.solid = true,
    this.translucent = false,
    this.cross = false,
    this.breakable = true,
    this.behavior = BlockBehavior.plain,
    required this.tiles,
  }) : blocksLight = blocksLight ?? opaque;

  final String name;

  /// Fully blocks light and hides neighbor faces.
  final bool opaque;

  /// Participates in the skylight/AO occlusion model independently of alpha
  /// cutout rendering. Leaves block light while keeping visible texture holes.
  final bool blocksLight;

  /// Player collides with it.
  final bool solid;

  /// Rendered in the translucent pass (fluids; glass keeps alpha cutout).
  final bool translucent;

  /// Rendered as X-cross sprite (plants), not a cube.
  final bool cross;

  /// Whether ordinary break interaction may remove this block.
  final bool breakable;

  final BlockBehavior behavior;

  /// Atlas tile index per [Face] (posX,negX,posY,negY,posZ,negZ).
  final List<int> tiles;
}

/// Atlas tile ids, row-major in a 16x16 atlas of 16px tiles.
/// Tile numbering is owned by the texture atlas generator; keep in sync.
abstract final class Tiles {
  static const int stone = 0;
  static const int dirt = 1;
  static const int grassTop = 2;
  static const int grassSide = 3;
  static const int sand = 4;
  static const int gravel = 5;
  static const int logSide = 6;
  static const int logTop = 7;
  static const int leaves = 8;
  static const int water = 9;
  static const int bedrock = 10;
  static const int oreCoal = 11;
  static const int oreIron = 12;
  static const int oreGold = 13;
  static const int planks = 14;
  static const int cobblestone = 15;
  static const int glass = 16;
  static const int brick = 17;
  static const int sponge = 18;
  static const int flowerDandelion = 19;
  static const int flowerRose = 20;
  static const int mushroomBrown = 21;
  static const int mushroomRed = 22;
  static const int lava = 23;
  static const int tntSide = 24;
  static const int tntTop = 25;
  static const int tntBottom = 26;
  static const int sapling = 27;
  static const int goldBlock = 28;
  static const int ironBlock = 29;
  static const int clothWhite = 30;
  static const int clothRed = 31;
  static const int clothOrange = 32;
  static const int clothYellow = 33;
  static const int clothLime = 34;
  static const int clothBlue = 35;
}

const List<BlockDef?> blockDefs = [
  null, // air
  BlockDef(
    name: 'stone',
    tiles: [
      Tiles.stone,
      Tiles.stone,
      Tiles.stone,
      Tiles.stone,
      Tiles.stone,
      Tiles.stone,
    ],
  ),
  BlockDef(
    name: 'dirt',
    tiles: [
      Tiles.dirt,
      Tiles.dirt,
      Tiles.dirt,
      Tiles.dirt,
      Tiles.dirt,
      Tiles.dirt,
    ],
  ),
  BlockDef(
    name: 'grass',
    tiles: [
      Tiles.grassSide,
      Tiles.grassSide,
      Tiles.grassTop,
      Tiles.dirt,
      Tiles.grassSide,
      Tiles.grassSide,
    ],
  ),
  BlockDef(
    name: 'sand',
    behavior: BlockBehavior.falling,
    tiles: [
      Tiles.sand,
      Tiles.sand,
      Tiles.sand,
      Tiles.sand,
      Tiles.sand,
      Tiles.sand,
    ],
  ),
  BlockDef(
    name: 'gravel',
    behavior: BlockBehavior.falling,
    tiles: [
      Tiles.gravel,
      Tiles.gravel,
      Tiles.gravel,
      Tiles.gravel,
      Tiles.gravel,
      Tiles.gravel,
    ],
  ),
  BlockDef(
    name: 'log_oak',
    tiles: [
      Tiles.logSide,
      Tiles.logSide,
      Tiles.logTop,
      Tiles.logTop,
      Tiles.logSide,
      Tiles.logSide,
    ],
  ),
  BlockDef(
    name: 'leaves_oak',
    opaque: false,
    blocksLight: true,
    tiles: [
      Tiles.leaves,
      Tiles.leaves,
      Tiles.leaves,
      Tiles.leaves,
      Tiles.leaves,
      Tiles.leaves,
    ],
  ),
  BlockDef(
    name: 'water',
    opaque: false,
    solid: false,
    translucent: true,
    breakable: false,
    behavior: BlockBehavior.water,
    tiles: [
      Tiles.water,
      Tiles.water,
      Tiles.water,
      Tiles.water,
      Tiles.water,
      Tiles.water,
    ],
  ),
  BlockDef(
    name: 'bedrock',
    breakable: false,
    tiles: [
      Tiles.bedrock,
      Tiles.bedrock,
      Tiles.bedrock,
      Tiles.bedrock,
      Tiles.bedrock,
      Tiles.bedrock,
    ],
  ),
  BlockDef(
    name: 'ore_coal',
    tiles: [
      Tiles.oreCoal,
      Tiles.oreCoal,
      Tiles.oreCoal,
      Tiles.oreCoal,
      Tiles.oreCoal,
      Tiles.oreCoal,
    ],
  ),
  BlockDef(
    name: 'ore_iron',
    tiles: [
      Tiles.oreIron,
      Tiles.oreIron,
      Tiles.oreIron,
      Tiles.oreIron,
      Tiles.oreIron,
      Tiles.oreIron,
    ],
  ),
  BlockDef(
    name: 'ore_gold',
    tiles: [
      Tiles.oreGold,
      Tiles.oreGold,
      Tiles.oreGold,
      Tiles.oreGold,
      Tiles.oreGold,
      Tiles.oreGold,
    ],
  ),
  BlockDef(
    name: 'planks_oak',
    tiles: [
      Tiles.planks,
      Tiles.planks,
      Tiles.planks,
      Tiles.planks,
      Tiles.planks,
      Tiles.planks,
    ],
  ),
  BlockDef(
    name: 'cobblestone',
    tiles: [
      Tiles.cobblestone,
      Tiles.cobblestone,
      Tiles.cobblestone,
      Tiles.cobblestone,
      Tiles.cobblestone,
      Tiles.cobblestone,
    ],
  ),
  BlockDef(
    name: 'glass',
    opaque: false,
    tiles: [
      Tiles.glass,
      Tiles.glass,
      Tiles.glass,
      Tiles.glass,
      Tiles.glass,
      Tiles.glass,
    ],
  ),
  BlockDef(
    name: 'brick',
    tiles: [
      Tiles.brick,
      Tiles.brick,
      Tiles.brick,
      Tiles.brick,
      Tiles.brick,
      Tiles.brick,
    ],
  ),
  BlockDef(
    name: 'sponge',
    behavior: BlockBehavior.sponge,
    tiles: [
      Tiles.sponge,
      Tiles.sponge,
      Tiles.sponge,
      Tiles.sponge,
      Tiles.sponge,
      Tiles.sponge,
    ],
  ),
  BlockDef(
    name: 'flower_dandelion',
    opaque: false,
    solid: false,
    cross: true,
    behavior: BlockBehavior.plant,
    tiles: [
      Tiles.flowerDandelion,
      Tiles.flowerDandelion,
      Tiles.flowerDandelion,
      Tiles.flowerDandelion,
      Tiles.flowerDandelion,
      Tiles.flowerDandelion,
    ],
  ),
  BlockDef(
    name: 'flower_rose',
    opaque: false,
    solid: false,
    cross: true,
    behavior: BlockBehavior.plant,
    tiles: [
      Tiles.flowerRose,
      Tiles.flowerRose,
      Tiles.flowerRose,
      Tiles.flowerRose,
      Tiles.flowerRose,
      Tiles.flowerRose,
    ],
  ),
  BlockDef(
    name: 'mushroom_brown',
    opaque: false,
    solid: false,
    cross: true,
    behavior: BlockBehavior.plant,
    tiles: [
      Tiles.mushroomBrown,
      Tiles.mushroomBrown,
      Tiles.mushroomBrown,
      Tiles.mushroomBrown,
      Tiles.mushroomBrown,
      Tiles.mushroomBrown,
    ],
  ),
  BlockDef(
    name: 'mushroom_red',
    opaque: false,
    solid: false,
    cross: true,
    behavior: BlockBehavior.plant,
    tiles: [
      Tiles.mushroomRed,
      Tiles.mushroomRed,
      Tiles.mushroomRed,
      Tiles.mushroomRed,
      Tiles.mushroomRed,
      Tiles.mushroomRed,
    ],
  ),
  BlockDef(
    name: 'lava',
    opaque: false,
    solid: false,
    translucent: true,
    breakable: false,
    behavior: BlockBehavior.lava,
    tiles: [
      Tiles.lava,
      Tiles.lava,
      Tiles.lava,
      Tiles.lava,
      Tiles.lava,
      Tiles.lava,
    ],
  ),
  BlockDef(
    name: 'tnt',
    behavior: BlockBehavior.tnt,
    tiles: [
      Tiles.tntSide,
      Tiles.tntSide,
      Tiles.tntTop,
      Tiles.tntBottom,
      Tiles.tntSide,
      Tiles.tntSide,
    ],
  ),
  BlockDef(
    name: 'sapling',
    opaque: false,
    solid: false,
    cross: true,
    behavior: BlockBehavior.plant,
    tiles: [
      Tiles.sapling,
      Tiles.sapling,
      Tiles.sapling,
      Tiles.sapling,
      Tiles.sapling,
      Tiles.sapling,
    ],
  ),
  BlockDef(
    name: 'gold_block',
    tiles: [
      Tiles.goldBlock,
      Tiles.goldBlock,
      Tiles.goldBlock,
      Tiles.goldBlock,
      Tiles.goldBlock,
      Tiles.goldBlock,
    ],
  ),
  BlockDef(
    name: 'iron_block',
    tiles: [
      Tiles.ironBlock,
      Tiles.ironBlock,
      Tiles.ironBlock,
      Tiles.ironBlock,
      Tiles.ironBlock,
      Tiles.ironBlock,
    ],
  ),
  BlockDef(
    name: 'cloth_white',
    tiles: [
      Tiles.clothWhite,
      Tiles.clothWhite,
      Tiles.clothWhite,
      Tiles.clothWhite,
      Tiles.clothWhite,
      Tiles.clothWhite,
    ],
  ),
  BlockDef(
    name: 'cloth_red',
    tiles: [
      Tiles.clothRed,
      Tiles.clothRed,
      Tiles.clothRed,
      Tiles.clothRed,
      Tiles.clothRed,
      Tiles.clothRed,
    ],
  ),
  BlockDef(
    name: 'cloth_orange',
    tiles: [
      Tiles.clothOrange,
      Tiles.clothOrange,
      Tiles.clothOrange,
      Tiles.clothOrange,
      Tiles.clothOrange,
      Tiles.clothOrange,
    ],
  ),
  BlockDef(
    name: 'cloth_yellow',
    tiles: [
      Tiles.clothYellow,
      Tiles.clothYellow,
      Tiles.clothYellow,
      Tiles.clothYellow,
      Tiles.clothYellow,
      Tiles.clothYellow,
    ],
  ),
  BlockDef(
    name: 'cloth_lime',
    tiles: [
      Tiles.clothLime,
      Tiles.clothLime,
      Tiles.clothLime,
      Tiles.clothLime,
      Tiles.clothLime,
      Tiles.clothLime,
    ],
  ),
  BlockDef(
    name: 'cloth_blue',
    tiles: [
      Tiles.clothBlue,
      Tiles.clothBlue,
      Tiles.clothBlue,
      Tiles.clothBlue,
      Tiles.clothBlue,
      Tiles.clothBlue,
    ],
  ),
];
