import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:minedart_core/minedart_core.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// How a chunk pass reaches the GPU.
enum UploadPath {
  /// The mesher's interleaved 80-byte vertices go up unchanged through
  /// `uploadVertexStreams` and a caller-declared layout.
  streams,

  /// De-interleave into structure-of-arrays and use `MeshGeometry.fromArrays`.
  arrays,
}

/// The minedart mesh ABI (20 floats per vertex):
/// position xyz @0, uv @12, color rgba @20, normal xyz @36, then 32 zero bytes
/// left over from flame_3d's fixed joint/weight layout. The unused tail is
/// bound to `texture_coords_1` and `tangent` so every engine input has data.
final VertexLayoutDescriptor minedartVertexLayout = VertexLayoutDescriptor(
  buffers: const [
    VertexBufferDescriptor(
      strideInBytes: VertexLayout.bytesPerVertex,
      attributes: [
        VertexAttributeDescriptor(
          name: 'position',
          format: gpu.VertexFormat.float32x3,
        ),
        VertexAttributeDescriptor(
          name: 'texture_coords',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 12,
        ),
        VertexAttributeDescriptor(
          name: 'color',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 20,
        ),
        VertexAttributeDescriptor(
          name: 'normal',
          format: gpu.VertexFormat.float32x3,
          offsetInBytes: 36,
        ),
        VertexAttributeDescriptor(
          name: 'texture_coords_1',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 48,
        ),
        VertexAttributeDescriptor(
          name: 'tangent',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 56,
        ),
      ],
    ),
    // Mirrors the engine's private 80-byte instance record, which every
    // caller-declared color-pass layout must end with.
    VertexBufferDescriptor(
      strideInBytes: 80,
      stepMode: gpu.VertexStepMode.instance,
      attributes: [
        VertexAttributeDescriptor(
          name: 'model_transform_0',
          format: gpu.VertexFormat.float32x4,
        ),
        VertexAttributeDescriptor(
          name: 'model_transform_1',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 16,
        ),
        VertexAttributeDescriptor(
          name: 'model_transform_2',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 32,
        ),
        VertexAttributeDescriptor(
          name: 'model_transform_3',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 48,
        ),
        VertexAttributeDescriptor(
          name: 'instance_color',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 64,
        ),
      ],
    ),
  ],
);

final vm.Aabb3 _chunkBounds = vm.Aabb3.minMax(
  vm.Vector3.zero(),
  vm.Vector3.all(WorldDims.chunkSize.toDouble()),
);
final vm.Sphere _chunkSphere = vm.Sphere.centerRadius(
  vm.Vector3.all(WorldDims.chunkSize / 2),
  WorldDims.chunkSize * math.sqrt(3) / 2,
);

/// Builds a new geometry for one chunk pass.
Geometry createChunkGeometry(
  UploadPath path,
  Float32List vertices,
  Uint16List indices,
) {
  switch (path) {
    case UploadPath.streams:
      final geometry = UnskinnedGeometry();
      uploadChunkStreams(geometry, vertices, indices);
      return geometry;
    case UploadPath.arrays:
      return _fromArrays(vertices, indices);
  }
}

/// Re-uploads [geometry] in place (streams path only), keeping its identity so
/// the scene's culling BVH is refit rather than rebuilt.
void uploadChunkStreams(
  UnskinnedGeometry geometry,
  Float32List vertices,
  Uint16List indices,
) {
  geometry
    ..uploadVertexStreams(
      [vertices],
      vertices.length ~/ VertexLayout.floatsPerVertex,
      indices: indices,
    )
    ..setVertexLayout(minedartVertexLayout)
    ..setLocalBounds(_chunkBounds, _chunkSphere);
}

MeshGeometry _fromArrays(Float32List vertices, Uint16List indices) {
  final count = vertices.length ~/ VertexLayout.floatsPerVertex;
  final positions = Float32List(count * 3);
  final texCoords = Float32List(count * 2);
  final colors = Float32List(count * 4);
  final normals = Float32List(count * 3);
  for (var v = 0; v < count; v++) {
    final s = v * VertexLayout.floatsPerVertex;
    positions[v * 3] = vertices[s];
    positions[v * 3 + 1] = vertices[s + 1];
    positions[v * 3 + 2] = vertices[s + 2];
    texCoords[v * 2] = vertices[s + 3];
    texCoords[v * 2 + 1] = vertices[s + 4];
    colors[v * 4] = vertices[s + 5];
    colors[v * 4 + 1] = vertices[s + 6];
    colors[v * 4 + 2] = vertices[s + 7];
    colors[v * 4 + 3] = vertices[s + 8];
    normals[v * 3] = vertices[s + 9];
    normals[v * 3 + 1] = vertices[s + 10];
    normals[v * 3 + 2] = vertices[s + 11];
  }
  return MeshGeometry.fromArrays(
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    colors: colors,
    indices: indices,
    bounds: _chunkBounds,
    retainCpuData: false,
  );
}
