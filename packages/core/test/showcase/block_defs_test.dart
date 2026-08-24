import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';

void main() {
  test('legacy ids stay stable and showcase ids occupy 22 through 32', () {
    expect([
      Blocks.stone,
      Blocks.dirt,
      Blocks.grass,
      Blocks.sand,
      Blocks.gravel,
      Blocks.logOak,
      Blocks.leavesOak,
      Blocks.water,
      Blocks.bedrock,
      Blocks.oreCoal,
      Blocks.oreIron,
      Blocks.oreGold,
      Blocks.planksOak,
      Blocks.cobblestone,
      Blocks.glass,
      Blocks.brick,
      Blocks.sponge,
      Blocks.flowerDandelion,
      Blocks.flowerRose,
      Blocks.mushroomBrown,
      Blocks.mushroomRed,
    ], orderedEquals(List.generate(21, (index) => index + 1)));
    expect([
      Blocks.lava,
      Blocks.tnt,
      Blocks.sapling,
      Blocks.goldBlock,
      Blocks.ironBlock,
      Blocks.clothWhite,
      Blocks.clothRed,
      Blocks.clothOrange,
      Blocks.clothYellow,
      Blocks.clothLime,
      Blocks.clothBlue,
    ], orderedEquals(List.generate(11, (index) => index + 22)));
    expect(Blocks.count, 33);
    expect(blockDefs, hasLength(Blocks.count));
    expect(blockDefs.skip(1), everyElement(isNotNull));
  });

  test('new atlas ids are stable and TNT has distinct top and bottom', () {
    expect(Tiles.lava, 23);
    expect(Tiles.tntSide, 24);
    expect(Tiles.tntTop, 25);
    expect(Tiles.tntBottom, 26);
    expect(Tiles.clothBlue, 35);

    final tnt = blockDefs[Blocks.tnt]!;
    expect(tnt.tiles[Face.posY], Tiles.tntTop);
    expect(tnt.tiles[Face.negY], Tiles.tntBottom);
    expect(tnt.tiles[Face.posX], Tiles.tntSide);
  });

  test('definitions own behavior and special break policy', () {
    expect(blockDefs[Blocks.sand]!.behavior, BlockBehavior.falling);
    expect(blockDefs[Blocks.gravel]!.behavior, BlockBehavior.falling);
    expect(blockDefs[Blocks.water]!.behavior, BlockBehavior.water);
    expect(blockDefs[Blocks.lava]!.behavior, BlockBehavior.lava);
    expect(blockDefs[Blocks.sponge]!.behavior, BlockBehavior.sponge);
    expect(blockDefs[Blocks.tnt]!.behavior, BlockBehavior.tnt);
    for (final id in [
      Blocks.flowerDandelion,
      Blocks.flowerRose,
      Blocks.mushroomBrown,
      Blocks.mushroomRed,
      Blocks.sapling,
    ]) {
      expect(blockDefs[id]!.behavior, BlockBehavior.plant);
    }

    expect(blockDefs[Blocks.bedrock]!.breakable, isFalse);
    expect(blockDefs[Blocks.water]!.breakable, isFalse);
    expect(blockDefs[Blocks.lava]!.breakable, isFalse);
    for (var id = 1; id < Blocks.count; id++) {
      if ({Blocks.bedrock, Blocks.water, Blocks.lava}.contains(id)) continue;
      expect(blockDefs[id]!.breakable, isTrue, reason: 'block id $id');
    }
  });
}
