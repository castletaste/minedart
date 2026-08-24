import 'dart:typed_data';

import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';

void main() {
  const mesher = ChunkMesher();

  test('single cube emits 24 vertices and 36 indices', () {
    final world = VoxelWorld();
    world.setBlock(8, 8, 8, Blocks.stone);

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));

    expect(mesh.opaqueVertexCount, 24);
    expect(mesh.opaqueIndices.length, 36);
    expect(mesh.translucentIndices, isEmpty);
  });

  test('two neighboring cubes emit ten faces', () {
    final world = VoxelWorld();
    world.setBlock(8, 8, 8, Blocks.stone);
    world.setBlock(9, 8, 8, Blocks.stone);

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));

    expect(mesh.opaqueVertexCount, 40);
    expect(mesh.opaqueIndices.length, 60);
  });

  test('fully enclosed chunk emits no geometry', () {
    final blocks = Uint16List(ChunkSnapshot.volume)
      ..fillRange(0, ChunkSnapshot.volume, Blocks.stone);
    final snapshot = ChunkSnapshot(
      cx: 1,
      cy: 1,
      cz: 1,
      revision: 7,
      blocks: blocks,
      skyHeight: Uint8List(ChunkSnapshot.skyArea),
    );

    final mesh = mesher.mesh(snapshot);

    expect(mesh.isEmpty, isTrue);
    expect(mesh.revision, 7);
    expect(mesh.chunkIndex, VoxelWorld.chunkIndexOf(1, 1, 1));
  });

  test('water has a 0.875 surface and no water-water face', () {
    final world = VoxelWorld();
    world.setBlock(8, 8, 8, Blocks.water);
    world.setBlock(9, 8, 8, Blocks.water);

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));

    expect(mesh.opaqueIndices, isEmpty);
    expect(mesh.translucentVertexCount, 40);
    expect(mesh.translucentIndices.length, 60);
    final yValues = <double>[];
    for (
      var offset = 1;
      offset < mesh.translucentVertices.length;
      offset += VertexLayout.floatsPerVertex
    ) {
      yValues.add(mesh.translucentVertices[offset]);
    }
    expect(yValues, contains(8.0));
    expect(yValues, contains(closeTo(8.875, 1e-6)));
    expect(yValues.reduce((a, b) => a > b ? a : b), closeTo(8.875, 1e-6));
  });

  test('lava shares fluid surface height and culls lava-lava face', () {
    final world = VoxelWorld();
    world.setBlock(8, 8, 8, Blocks.lava);
    world.setBlock(9, 8, 8, Blocks.lava);

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));

    expect(mesh.translucentVertexCount, 40);
    expect(mesh.translucentIndices.length, 60);
    final yValues = <double>{};
    for (
      var offset = 1;
      offset < mesh.translucentVertices.length;
      offset += VertexLayout.floatsPerVertex
    ) {
      yValues.add(mesh.translucentVertices[offset]);
    }
    expect(yValues, contains(closeTo(8.875, 1e-6)));
  });

  test('ambient occlusion darkens a blocked top corner', () {
    final world = VoxelWorld();
    world.setBlock(8, 8, 8, Blocks.stone);
    world.setBlock(7, 9, 8, Blocks.stone);
    world.setBlock(8, 9, 7, Blocks.stone);
    world.setBlock(7, 9, 7, Blocks.stone);

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));
    final lights = _topFaceLights(mesh.opaqueVertices, 8, 8, 8);

    expect(lights.reduce((a, b) => a < b ? a : b), closeTo(0.35, 1e-6));
    expect(lights.reduce((a, b) => a > b ? a : b), closeTo(1.0, 1e-6));
  });

  test('overhang changes direct skylight base from 1.0 to 0.6', () {
    final world = VoxelWorld();
    world.setBlock(8, 8, 8, Blocks.stone);
    world.setBlock(8, 10, 8, Blocks.stone);

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));
    final lights = _topFaceLights(mesh.opaqueVertices, 8, 8, 8);

    expect(lights, everyElement(closeTo(0.6, 1e-6)));
  });

  test('cutout leaves cast the same direct skylight shadow', () {
    final world = VoxelWorld();
    world.setBlock(8, 8, 8, Blocks.stone);
    world.setBlock(8, 10, 8, Blocks.leavesOak);

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));
    final lights = _topFaceLights(mesh.opaqueVertices, 8, 8, 8);

    expect(lights, everyElement(closeTo(0.6, 1e-6)));
  });

  test('cross block emits two quads without coplanar duplicates', () {
    final world = VoxelWorld();
    world.setBlock(8, 8, 8, Blocks.flowerDandelion);

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));

    // Materials use CullMode.none, so each quad is already double-sided.
    // Emitting reversed copies here would cause depth fighting on Metal/WebGPU.
    expect(mesh.opaqueVertexCount, 8);
    expect(mesh.opaqueIndices.length ~/ 3, 4);
    expect(mesh.translucentIndices, isEmpty);
  });

  test('a glass-leaves interface keeps one leaves-owned face', () {
    final world = VoxelWorld()
      ..setBlock(8, 8, 8, Blocks.leavesOak)
      ..setBlock(9, 8, 8, Blocks.glass);

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));

    // Ten exterior faces plus one shared, double-sided interior face.
    expect(mesh.opaqueVertexCount, 44);
    final sharedFace =
        (mesh.opaqueVertexCount - 4) * VertexLayout.floatsPerVertex;
    expect(mesh.opaqueVertices[sharedFace + 9], 1);
    expect(mesh.opaqueVertices[sharedFace + 10], 0);
    expect(mesh.opaqueVertices[sharedFace + 11], 0);
  });

  test(
    'alternating glass and leaves stays Uint16-safe without disappearing',
    () {
      final snapshot = _filledSnapshot(
        (x, y, z) => (x + y + z).isEven ? Blocks.glass : Blocks.leavesOak,
      );

      final mesh = mesher.mesh(snapshot);

      // Every interior boundary keeps one double-sided, visually stronger face
      // instead of two coplanar faces. Outer faces are all retained.
      expect(mesh.isEmpty, isFalse);
      expect(mesh.opaqueVertexCount, 52224);
      expect(mesh.opaqueIndices.length, 78336);
      expect(mesh.translucentIndices, isEmpty);
      _expectUint16Surface(mesh.opaqueVertices, mesh.opaqueIndices);
    },
  );

  test('an exact-limit cross and stone chunk may use index 65535', () {
    final snapshot = _filledSnapshot(
      (x, y, z) => (x + y + z).isEven ? Blocks.flowerDandelion : Blocks.stone,
    );

    final mesh = mesher.mesh(snapshot);

    expect(mesh.isEmpty, isFalse);
    expect(mesh.opaqueVertexCount, 65536);
    expect(mesh.opaqueIndices.length, 98304);
    _expectUint16Surface(mesh.opaqueVertices, mesh.opaqueIndices);
    expect(mesh.opaqueIndices.reduce((a, b) => a > b ? a : b), 65535);
  });

  test('adversarial overflow keeps the exterior and caps interior faces', () {
    final snapshot = _filledSnapshot((x, y, z) {
      final boundaryAxes =
          (x == 0 || x == 15 ? 1 : 0) +
          (y == 0 || y == 15 ? 1 : 0) +
          (z == 0 || z == 15 ? 1 : 0);
      if ((x + y + z).isEven && boundaryAxes <= 1) {
        return Blocks.flowerDandelion;
      }
      return (x + y + z).isEven ? Blocks.leavesOak : Blocks.glass;
    });

    final mesh = mesher.mesh(snapshot);

    // This fixture requests 16,388 quads. Four interior interfaces are
    // deterministically omitted, while all 948 outer cube faces remain.
    expect(mesh.opaqueVertexCount, 65536);
    expect(mesh.opaqueIndices.length, 98304);
    expect(_outerCubeQuadCount(mesh.opaqueVertices), 948);
    _expectUint16Surface(mesh.opaqueVertices, mesh.opaqueIndices);
  });

  test('meshing the same snapshot is byte-for-byte deterministic', () {
    final world = VoxelWorld();
    world.setBlock(8, 8, 8, Blocks.grass);
    world.setBlock(9, 8, 8, Blocks.water);
    world.setBlock(8, 9, 8, Blocks.flowerRose);
    final snapshot = ChunkSnapshot.capture(world, 0, 0, 0);

    final first = mesher.mesh(snapshot);
    final second = mesher.mesh(snapshot);

    expect(second.opaqueVertices, orderedEquals(first.opaqueVertices));
    expect(second.opaqueIndices, orderedEquals(first.opaqueIndices));
    expect(
      second.translucentVertices,
      orderedEquals(first.translucentVertices),
    );
    expect(second.translucentIndices, orderedEquals(first.translucentIndices));
  });
}

ChunkSnapshot _filledSnapshot(int Function(int x, int y, int z) blockAt) {
  final blocks = Uint16List(ChunkSnapshot.volume);
  for (var y = 0; y < WorldDims.chunkSize; y++) {
    for (var z = 0; z < WorldDims.chunkSize; z++) {
      for (var x = 0; x < WorldDims.chunkSize; x++) {
        blocks[ChunkSnapshot.indexOf(x + 1, y + 1, z + 1)] = blockAt(x, y, z);
      }
    }
  }
  return ChunkSnapshot(
    cx: 1,
    cy: 1,
    cz: 1,
    revision: 1,
    blocks: blocks,
    skyHeight: Uint8List(ChunkSnapshot.skyArea),
  );
}

void _expectUint16Surface(Float32List vertices, Uint16List indices) {
  expect(vertices.length % VertexLayout.floatsPerVertex, 0);
  final vertexCount = vertices.length ~/ VertexLayout.floatsPerVertex;
  expect(vertexCount, lessThanOrEqualTo(65536));
  expect(indices, isNotEmpty);
  expect(indices.reduce((a, b) => a > b ? a : b), lessThan(vertexCount));
}

int _outerCubeQuadCount(Float32List vertices) {
  const stride = VertexLayout.floatsPerVertex;
  var count = 0;
  for (var first = 0; first < vertices.length ~/ stride; first += 4) {
    final offset = first * stride;
    final nx = vertices[offset + 9];
    final ny = vertices[offset + 10];
    final nz = vertices[offset + 11];
    final axisAligned =
        (nx.abs() == 1 && ny == 0 && nz == 0) ||
        (ny.abs() == 1 && nx == 0 && nz == 0) ||
        (nz.abs() == 1 && nx == 0 && ny == 0);
    if (!axisAligned) continue;

    var outside = true;
    for (var corner = 0; corner < 4; corner++) {
      final vertex = (first + corner) * stride;
      final x = vertices[vertex];
      final y = vertices[vertex + 1];
      final z = vertices[vertex + 2];
      if (!((nx == -1 && x == 0) ||
          (nx == 1 && x == 16) ||
          (ny == -1 && y == 0) ||
          (ny == 1 && y == 16) ||
          (nz == -1 && z == 0) ||
          (nz == 1 && z == 16))) {
        outside = false;
        break;
      }
    }
    if (outside) count++;
  }
  return count;
}

List<double> _topFaceLights(
  Float32List vertices,
  int blockX,
  int blockY,
  int blockZ,
) {
  const stride = VertexLayout.floatsPerVertex;
  for (
    var firstVertex = 0;
    firstVertex < vertices.length ~/ stride;
    firstVertex += 4
  ) {
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minZ = double.infinity;
    var maxZ = double.negativeInfinity;
    var matches = true;
    for (var corner = 0; corner < 4; corner++) {
      final offset = (firstVertex + corner) * stride;
      final x = vertices[offset];
      final y = vertices[offset + 1];
      final z = vertices[offset + 2];
      if (y != blockY + 1 ||
          vertices[offset + 9] != 0 ||
          vertices[offset + 10] != 1 ||
          vertices[offset + 11] != 0) {
        matches = false;
        break;
      }
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (z < minZ) minZ = z;
      if (z > maxZ) maxZ = z;
    }
    if (matches &&
        minX == blockX &&
        maxX == blockX + 1 &&
        minZ == blockZ &&
        maxZ == blockZ + 1) {
      return List<double>.generate(
        4,
        (corner) => vertices[(firstVertex + corner) * stride + 5],
        growable: false,
      );
    }
  }
  throw StateError('Top face for ($blockX, $blockY, $blockZ) not found');
}
