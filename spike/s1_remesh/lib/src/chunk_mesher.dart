import 'dart:typed_data';

const int chunkSize = 16;
const int floatsPerVertex = 20;
const int verticesPerQuad = 4;
const int indicesPerQuad = 6;

/// normal xyz followed by four xyz corner offsets.
const List<List<int>> _faces = [
  [-1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0],
  [1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 1],
  [0, -1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 1],
  [0, 1, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0],
  [0, 0, -1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0],
  [0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1],
];

final class ChunkMeshData {
  const ChunkMeshData({
    required this.vertices,
    required this.indices,
    required this.quadCount,
  });

  final Float32List vertices;
  final Uint16List indices;
  final int quadCount;

  int get vertexCount => quadCount * verticesPerQuad;
  int get indexCount => quadCount * indicesPerQuad;
}

/// Stable ~15% occupancy gives a representative culled mesh in the requested
/// 2k-4k visible-quad range, while keeping the source chunk exactly 16^3.
Uint16List makeBenchmarkChunk() {
  final blocks = Uint16List(chunkSize * chunkSize * chunkSize);
  var state = 0x6d2b79f5;
  for (var i = 0; i < blocks.length; i++) {
    state ^= (state << 13) & 0xffffffff;
    state ^= state >>> 17;
    state ^= (state << 5) & 0xffffffff;
    blocks[i] = (state & 0xffff) < 10000 ? 1 : 0;
  }
  return blocks;
}

ChunkMeshData meshChunk(Uint16List blocks) {
  if (blocks.length != chunkSize * chunkSize * chunkSize) {
    throw ArgumentError.value(blocks.length, 'blocks.length', 'must be 4096');
  }

  var quadCount = 0;
  for (var z = 0; z < chunkSize; z++) {
    for (var y = 0; y < chunkSize; y++) {
      for (var x = 0; x < chunkSize; x++) {
        if (!_solid(blocks, x, y, z)) continue;
        for (final face in _faces) {
          if (!_solid(blocks, x + face[0], y + face[1], z + face[2])) {
            quadCount++;
          }
        }
      }
    }
  }

  final vertices = Float32List(quadCount * verticesPerQuad * floatsPerVertex);
  final indices = Uint16List(quadCount * indicesPerQuad);
  var vertexOffset = 0;
  var indexOffset = 0;
  var vertexIndex = 0;

  for (var z = 0; z < chunkSize; z++) {
    for (var y = 0; y < chunkSize; y++) {
      for (var x = 0; x < chunkSize; x++) {
        if (!_solid(blocks, x, y, z)) continue;
        for (final face in _faces) {
          if (_solid(blocks, x + face[0], y + face[1], z + face[2])) {
            continue;
          }
          for (var corner = 0; corner < 4; corner++) {
            final cornerOffset = 3 + corner * 3;
            vertices[vertexOffset] = (x + face[cornerOffset]).toDouble();
            vertices[vertexOffset + 1] = (y + face[cornerOffset + 1])
                .toDouble();
            vertices[vertexOffset + 2] = (z + face[cornerOffset + 2])
                .toDouble();
            vertices[vertexOffset + 3] = corner == 1 || corner == 2 ? 1 : 0;
            vertices[vertexOffset + 4] = corner >= 2 ? 1 : 0;
            vertices[vertexOffset + 5] = 1;
            vertices[vertexOffset + 6] = 1;
            vertices[vertexOffset + 7] = 1;
            vertices[vertexOffset + 8] = 1;
            vertices[vertexOffset + 9] = face[0].toDouble();
            vertices[vertexOffset + 10] = face[1].toDouble();
            vertices[vertexOffset + 11] = face[2].toDouble();
            vertexOffset += floatsPerVertex;
          }
          indices[indexOffset] = vertexIndex;
          indices[indexOffset + 1] = vertexIndex + 1;
          indices[indexOffset + 2] = vertexIndex + 2;
          indices[indexOffset + 3] = vertexIndex;
          indices[indexOffset + 4] = vertexIndex + 2;
          indices[indexOffset + 5] = vertexIndex + 3;
          indexOffset += indicesPerQuad;
          vertexIndex += verticesPerQuad;
        }
      }
    }
  }

  return ChunkMeshData(
    vertices: vertices,
    indices: indices,
    quadCount: quadCount,
  );
}

bool _solid(Uint16List blocks, int x, int y, int z) {
  if (x < 0 ||
      y < 0 ||
      z < 0 ||
      x >= chunkSize ||
      y >= chunkSize ||
      z >= chunkSize) {
    return false;
  }
  return blocks[x + chunkSize * (y + chunkSize * z)] != 0;
}

int meshChecksum(ChunkMeshData data) {
  var hash = data.quadCount;
  for (var i = 0; i < data.vertices.length; i += 97) {
    hash = 0x1fffffff & (hash * 31 + data.vertices[i].toInt());
  }
  for (var i = 0; i < data.indices.length; i += 89) {
    hash = 0x1fffffff & (hash * 31 + data.indices[i]);
  }
  return hash;
}
