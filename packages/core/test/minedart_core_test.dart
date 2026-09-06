import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';

void main() {
  test('block pack/unpack roundtrip', () {
    final raw = Blocks.pack(Blocks.grass, 5);
    expect(Blocks.id(raw), Blocks.grass);
    expect(Blocks.meta(raw), 5);
  });

  test('world set/get + dirty neighbors on border', () {
    final w = VoxelWorld();
    final dirty = w.setBlock(16, 10, 10, Blocks.stone);
    expect(w.blockAt(16, 10, 10), Blocks.stone);
    expect(dirty.contains(VoxelWorld.chunkIndexOf(1, 0, 0)), isTrue);
    expect(dirty.contains(VoxelWorld.chunkIndexOf(0, 0, 0)), isTrue);
  });

  test('invalid raw block leaves every world invariant unchanged', () {
    final world = VoxelWorld()..setBlock(5, 20, 5, Blocks.stone);
    final chunk = world.chunkAt(0, 1, 0);
    final revision = chunk.revision;
    final nonAir = chunk.nonAirCount;
    final sky = world.skyHeight[5 + 5 * WorldDims.worldBlocksX];

    expect(() => world.setBlock(5, 20, 5, Blocks.count), throwsRangeError);

    expect(world.blockAt(5, 20, 5), Blocks.stone);
    expect(chunk.revision, revision);
    expect(chunk.nonAirCount, nonAir);
    expect(world.skyHeight[5 + 5 * WorldDims.worldBlocksX], sky);
  });

  test('invalid raw block leaves change builder bookkeeping unchanged', () {
    final world = VoxelWorld();
    final builder = WorldChangeSetBuilder(world);

    expect(() => builder.set(1, 2, 3, 0x0fff), throwsRangeError);

    expect(builder.build().isEmpty, isTrue);
    expect(world.blockAt(1, 2, 3), Blocks.air);
  });

  test('AO halo dirties the diagonal chunk across an x-z edge', () {
    final world = VoxelWorld()
      // Keep skylight unchanged so this isolates the one-voxel block halo.
      ..setBlock(16, 63, 16, Blocks.stone);

    final dirty = world.setBlock(16, 8, 16, Blocks.stone);

    expect(
      dirty,
      equals(_chunkIndices([(0, 0, 0), (1, 0, 0), (0, 0, 1), (1, 0, 1)])),
    );
  });

  test('AO halo dirties all eight chunks across an x-y-z corner', () {
    final world = VoxelWorld()
      // Keep skylight unchanged so this isolates the one-voxel block halo.
      ..setBlock(16, 63, 16, Blocks.stone);

    final dirty = world.setBlock(16, 16, 16, Blocks.stone);

    expect(
      dirty,
      equals(
        _chunkIndices([
          for (var cy = 0; cy <= 1; cy++)
            for (var cz = 0; cz <= 1; cz++)
              for (var cx = 0; cx <= 1; cx++) (cx, cy, cz),
        ]),
      ),
    );
  });

  test('skylight range on a chunk boundary dirties the chunk below', () {
    final world = VoxelWorld()..setBlock(8, 31, 8, Blocks.stone);

    final dirty = world.setBlock(8, 40, 8, Blocks.stone);

    expect(world.skyHeight[8 + 8 * WorldDims.worldBlocksX], 41);
    expect(dirty, contains(VoxelWorld.chunkIndexOf(0, 1, 0)));
    expect(dirty, contains(VoxelWorld.chunkIndexOf(0, 2, 0)));
  });

  test('AO halo includes all positive-side corner combinations', () {
    final world = VoxelWorld()
      // Keep skylight unchanged so this isolates the one-voxel block halo.
      ..setBlock(31, 63, 31, Blocks.stone);

    final dirty = world.setBlock(31, 31, 31, Blocks.stone);

    expect(
      dirty,
      equals(
        _chunkIndices([
          for (var cy = 1; cy <= 2; cy++)
            for (var cz = 1; cz <= 2; cz++)
              for (var cx = 1; cx <= 2; cx++) (cx, cy, cz),
        ]),
      ),
    );
  });

  test('skylight heightmap updates on place/remove', () {
    final w = VoxelWorld();
    expect(w.inSkylight(5, 5, 5), isTrue);
    w.setBlock(5, 20, 5, Blocks.stone);
    expect(w.inSkylight(5, 5, 5), isFalse);
    expect(w.inSkylight(5, 21, 5), isTrue);
    w.setBlock(5, 20, 5, Blocks.air);
    expect(w.inSkylight(5, 5, 5), isTrue);
  });

  test('cutout leaves cast skylight while remaining non-opaque', () {
    final world = VoxelWorld();
    expect(blockDefs[Blocks.leavesOak]!.opaque, isFalse);
    expect(blockDefs[Blocks.leavesOak]!.blocksLight, isTrue);

    world.setBlock(5, 20, 5, Blocks.leavesOak);
    expect(world.skyHeight[5 + 5 * WorldDims.worldBlocksX], 21);
    expect(world.inSkylight(5, 5, 5), isFalse);

    world.setBlock(5, 20, 5, Blocks.air);
    expect(world.inSkylight(5, 5, 5), isTrue);
  });
}

Set<int> _chunkIndices(Iterable<(int, int, int)> coordinates) => {
  for (final (cx, cy, cz) in coordinates) VoxelWorld.chunkIndexOf(cx, cy, cz),
};
