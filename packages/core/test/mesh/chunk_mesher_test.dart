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

  test('water and lava render every level and falling metadata height', () {
    for (final liquidId in [Blocks.water, Blocks.lava]) {
      for (var metadata = 0; metadata < 16; metadata++) {
        final world = VoxelWorld();
        final raw = Blocks.pack(liquidId, metadata);
        for (var z = 7; z <= 9; z++) {
          for (var x = 7; x <= 9; x++) {
            world.setBlock(x, 8, z, raw);
          }
        }

        final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));
        final top = _topQuad(mesh.translucentVertices, 8, 8, 8);
        final expectedHeight = LiquidState.surfaceHeight(raw);

        expect(
          top.map((vertex) => vertex.y - 8),
          everyElement(closeTo(expectedHeight, 1e-6)),
          reason: 'liquid=$liquidId metadata=$metadata',
        );
      }
    }
  });

  test('source and falling samples have Alpha eleven-fold weight', () {
    for (final weightedRaw in [
      LiquidState.pack(Blocks.water, 0),
      LiquidState.pack(Blocks.water, 7, falling: true),
    ]) {
      final world = VoxelWorld()
        ..setBlock(8, 8, 8, LiquidState.pack(Blocks.water, 4))
        ..setBlock(9, 8, 8, weightedRaw)
        ..setBlock(8, 8, 9, LiquidState.pack(Blocks.water, 7));

      final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));
      final top = _topQuad(mesh.translucentVertices, 8, 8, 8);

      // At corner (9, 9): level 4 has height 4/9, level 7 has 1/9,
      // source/falling has height 8/9 with weight 11, and air has height 0.
      expect(
        _heightAt(top, 9, 9) - 8,
        closeTo((4 / 9 + 1 / 9 + 11 * 8 / 9) / 14, 1e-6),
      );
    }
  });

  test('same-fluid cell above raises its shared corner to full height', () {
    final world = VoxelWorld()
      ..setBlock(8, 8, 8, LiquidState.pack(Blocks.water, 7))
      ..setBlock(9, 9, 9, LiquidState.pack(Blocks.water, 7));

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));
    final top = _topQuad(mesh.translucentVertices, 8, 8, 8);

    expect(_heightAt(top, 9, 9), closeTo(9, 1e-6));
    expect(_heightAt(top, 8, 8), lessThan(9));
  });

  test('stacked falling-liquid side faces meet without vertical gaps', () {
    final world = VoxelWorld();
    for (var y = 8; y <= 10; y++) {
      world.setBlock(8, y, 8, LiquidState.pack(Blocks.water, 0, falling: true));
    }

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));
    final sides = <List<_MeshVertex>>[
      for (var y = 8; y <= 10; y++)
        _axisQuad(
          mesh.translucentVertices,
          normalX: -1,
          normalY: 0,
          normalZ: 0,
          matches: (quad) =>
              quad.every((vertex) => vertex.x == 8) &&
              quad.map((vertex) => vertex.y).reduce(_min) == y &&
              quad.map((vertex) => vertex.z).reduce(_min) == 8 &&
              quad.map((vertex) => vertex.z).reduce(_max) == 9,
        ),
    ];

    for (var index = 0; index < sides.length - 1; index++) {
      final lowerTop = sides[index].map((vertex) => vertex.y).reduce(_max);
      final upperBottom = sides[index + 1]
          .map((vertex) => vertex.y)
          .reduce(_min);
      expect(lowerTop, upperBottom, reason: 'boundary ${index + 9}');
    }
    expect(
      sides.last.map((vertex) => vertex.y).reduce(_max),
      closeTo(10 + (11 * 8 / 9) / 14, 1e-6),
    );
  });

  test('liquid side tops match corners and UVs retain texel scale', () {
    final world = VoxelWorld()
      ..setBlock(8, 8, 8, LiquidState.pack(Blocks.water, 4))
      ..setBlock(8, 8, 9, LiquidState.pack(Blocks.water, 0));

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));
    final top = _topQuad(mesh.translucentVertices, 8, 8, 8);
    final side = _axisQuad(
      mesh.translucentVertices,
      normalX: -1,
      normalY: 0,
      normalZ: 0,
      matches: (quad) =>
          quad.every((vertex) => vertex.x == 8) &&
          quad.any((vertex) => vertex.y == 8) &&
          quad.map((vertex) => vertex.z).reduce(_min) == 8 &&
          quad.map((vertex) => vertex.z).reduce(_max) == 9,
    );

    const v0 = 0.5 / 256;
    const v1 = 1 / 16 - 0.5 / 256;
    final bottom = side.where((vertex) => vertex.y == 8).toList();
    final sideTop = side.where((vertex) => vertex.y > 8).toList();
    expect(bottom, hasLength(2));
    expect(sideTop, hasLength(2));
    for (final vertex in bottom) {
      expect(vertex.v, closeTo(v1, 1e-6));
    }
    for (final vertex in sideTop) {
      final topY = _heightAt(top, vertex.x, vertex.z);
      expect(vertex.y, closeTo(topY, 1e-6));
      final height = vertex.y - 8;
      expect(vertex.v, closeTo(v1 - height * (v1 - v0), 1e-6));
    }
  });

  test('different metadata of the same fluid culls their interface', () {
    final world = VoxelWorld()
      ..setBlock(8, 8, 8, LiquidState.pack(Blocks.lava, 0))
      ..setBlock(9, 8, 8, LiquidState.pack(Blocks.lava, 7, falling: true));

    final mesh = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));

    expect(mesh.opaqueIndices, isEmpty);
    expect(mesh.translucentVertexCount, 40);
    expect(mesh.translucentIndices.length, 60);
    expect(
      _hasAxisQuadAt(
        mesh.translucentVertices,
        x: 9,
        normalX: 1,
        normalY: 0,
        normalZ: 0,
      ),
      isFalse,
    );
    expect(
      _hasAxisQuadAt(
        mesh.translucentVertices,
        x: 9,
        normalX: -1,
        normalY: 0,
        normalZ: 0,
      ),
      isFalse,
    );
  });

  test('liquid heights and culling are continuous across chunk borders', () {
    final world = VoxelWorld()
      ..setBlock(15, 8, 8, LiquidState.pack(Blocks.water, 0))
      ..setBlock(16, 8, 8, LiquidState.pack(Blocks.water, 7));

    final left = mesher.mesh(ChunkSnapshot.capture(world, 0, 0, 0));
    final right = mesher.mesh(ChunkSnapshot.capture(world, 1, 0, 0));
    final leftTop = _topQuad(left.translucentVertices, 15, 8, 8);
    final rightTop = _topQuad(right.translucentVertices, 0, 8, 8);

    for (final z in [8.0, 9.0]) {
      expect(
        _heightAt(leftTop, 16, z),
        closeTo(_heightAt(rightTop, 0, z), 1e-6),
      );
    }
    expect(left.translucentVertexCount, 20);
    expect(right.translucentVertexCount, 20);
    expect(
      _hasAxisQuadAt(
        left.translucentVertices,
        x: 16,
        normalX: 1,
        normalY: 0,
        normalZ: 0,
      ),
      isFalse,
    );
    expect(
      _hasAxisQuadAt(
        right.translucentVertices,
        x: 0,
        normalX: -1,
        normalY: 0,
        normalZ: 0,
      ),
      isFalse,
    );
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

typedef _MeshVertex = ({double x, double y, double z, double u, double v});

List<_MeshVertex> _topQuad(
  Float32List vertices,
  int blockX,
  int blockY,
  int blockZ,
) => _axisQuad(
  vertices,
  normalX: 0,
  normalY: 1,
  normalZ: 0,
  matches: (quad) =>
      quad.map((vertex) => vertex.x).reduce(_min) == blockX &&
      quad.map((vertex) => vertex.x).reduce(_max) == blockX + 1 &&
      quad.map((vertex) => vertex.z).reduce(_min) == blockZ &&
      quad.map((vertex) => vertex.z).reduce(_max) == blockZ + 1 &&
      quad.every((vertex) => vertex.y >= blockY && vertex.y <= blockY + 1),
);

List<_MeshVertex> _axisQuad(
  Float32List vertices, {
  required double normalX,
  required double normalY,
  required double normalZ,
  required bool Function(List<_MeshVertex> quad) matches,
}) {
  for (final quad in _axisQuads(
    vertices,
    normalX: normalX,
    normalY: normalY,
    normalZ: normalZ,
  )) {
    if (matches(quad)) return quad;
  }
  throw StateError(
    'No matching quad with normal ($normalX, $normalY, $normalZ)',
  );
}

Iterable<List<_MeshVertex>> _axisQuads(
  Float32List vertices, {
  required double normalX,
  required double normalY,
  required double normalZ,
}) sync* {
  const stride = VertexLayout.floatsPerVertex;
  final vertexCount = vertices.length ~/ stride;
  for (var first = 0; first < vertexCount; first += 4) {
    final firstOffset = first * stride;
    if (vertices[firstOffset + 9] != normalX ||
        vertices[firstOffset + 10] != normalY ||
        vertices[firstOffset + 11] != normalZ) {
      continue;
    }
    yield List<_MeshVertex>.generate(4, (corner) {
      final offset = (first + corner) * stride;
      return (
        x: vertices[offset],
        y: vertices[offset + 1],
        z: vertices[offset + 2],
        u: vertices[offset + 3],
        v: vertices[offset + 4],
      );
    }, growable: false);
  }
}

bool _hasAxisQuadAt(
  Float32List vertices, {
  required double x,
  required double normalX,
  required double normalY,
  required double normalZ,
}) {
  for (final quad in _axisQuads(
    vertices,
    normalX: normalX,
    normalY: normalY,
    normalZ: normalZ,
  )) {
    if (quad.every((vertex) => vertex.x == x)) return true;
  }
  return false;
}

double _heightAt(List<_MeshVertex> quad, num x, num z) =>
    quad.singleWhere((vertex) => vertex.x == x && vertex.z == z).y;

double _min(double left, double right) => left < right ? left : right;

double _max(double left, double right) => left > right ? left : right;

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
