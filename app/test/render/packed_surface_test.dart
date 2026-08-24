import 'dart:typed_data';

import 'package:flame_3d/game.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/render/packed_surface.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('PackedSurface', () {
    test('known bounds defer positions until the public getter is read', () {
      final vertices = _vertices(<(double, double, double)>[
        (-1.5, 2, 4.25),
        (3, -2.5, 0.5),
      ]);
      final indices = Uint16List.fromList(<int>[0, 1, 0]);
      final knownBounds = Aabb3.minMax(
        Vector3(-1.5, -2.5, 0.5),
        Vector3(3, 2, 4.25),
      );
      final surface = PackedSurface(
        vertices: vertices,
        indices: indices,
        material: Material.defaultMaterial,
        aabb: knownBounds,
      );

      expect(VertexLayout.floatsPerVertex, 20);
      expect(surface.vertexCount, 2);
      expect(surface.verticesBytes, 2 * 20 * Float32List.bytesPerElement);
      expect(surface.indexCount, 3);
      expect(surface.indicesBytes, 3 * Uint16List.bytesPerElement);
      expect(surface.indices, isA<Uint16List>());
      expect(identical(surface.indices, indices), isTrue);
      expect(surface.hasMaterializedPositions, isFalse);

      _expectVector(surface.aabb.min, -1.5, -2.5, 0.5);
      _expectVector(surface.aabb.max, 3, 2, 4.25);
      expect(surface.hasMaterializedPositions, isFalse);

      final positions = surface.positions;
      expect(positions, isA<Float32List>());
      expect(positions, orderedEquals(<double>[-1.5, 2, 4.25, 3, -2.5, 0.5]));
      expect(surface.hasMaterializedPositions, isTrue);
      expect(identical(surface.positions, positions), isTrue);
    });

    test('unknown bounds retain eager positions and calculated AABB', () {
      final vertices = _vertices(<(double, double, double)>[
        (7, -1, 2),
        (-4, 8, 0),
        (1, 3, -6),
      ]);
      final surface = PackedSurface(
        vertices: vertices,
        indices: Uint16List.fromList(<int>[0, 1, 2]),
        material: Material.defaultMaterial,
      );

      expect(surface.hasMaterializedPositions, isTrue);
      expect(
        surface.positions,
        orderedEquals(<double>[7, -1, 2, -4, 8, 0, 1, 3, -6]),
      );
      _expectVector(surface.aabb.min, -4, -1, -6);
      _expectVector(surface.aabb.max, 7, 8, 2);
    });

    test('empty unknown geometry keeps the existing zero AABB behavior', () {
      final surface = PackedSurface(
        vertices: Float32List(0),
        indices: Uint16List(0),
        material: Material.defaultMaterial,
      );

      expect(surface.hasMaterializedPositions, isTrue);
      expect(surface.positions, isEmpty);
      _expectVector(surface.aabb.min, 0, 0, 0);
      _expectVector(surface.aabb.max, 0, 0, 0);
    });

    test('malformed stride and indices retain their prior behavior', () {
      final partialVertex = Float32List(VertexLayout.floatsPerVertex + 1)
        ..[0] = 1
        ..[1] = 2
        ..[2] = 3;

      // Without known bounds, the existing AABB scan still reports the short
      // trailing position through its RangeError.
      expect(
        () => PackedSurface(
          vertices: partialVertex,
          indices: Uint16List(0),
          material: Material.defaultMaterial,
        ),
        throwsRangeError,
      );

      final invalidIndices = Uint16List.fromList(<int>[65535]);
      final surface = PackedSurface(
        vertices: partialVertex,
        indices: invalidIndices,
        material: Material.defaultMaterial,
        aabb: Aabb3.minMax(Vector3(1, 2, 3), Vector3(1, 2, 3)),
      );

      // Known bounds historically bypass AABB validation, vertex count floors
      // to complete 20-float records, and index values are not range-checked.
      expect(surface.vertexCount, 1);
      expect(surface.positions, orderedEquals(<double>[1, 2, 3]));
      expect(identical(surface.indices, invalidIndices), isTrue);
      expect(surface.indices.single, 65535);
    });
  });
}

Float32List _vertices(List<(double, double, double)> positions) {
  final vertices = Float32List(positions.length * VertexLayout.floatsPerVertex);
  for (final (index, position) in positions.indexed) {
    final offset = index * VertexLayout.floatsPerVertex;
    vertices[offset] = position.$1;
    vertices[offset + 1] = position.$2;
    vertices[offset + 2] = position.$3;
  }
  return vertices;
}

void _expectVector(Vector3 actual, double x, double y, double z) {
  expect(actual.x, x);
  expect(actual.y, y);
  expect(actual.z, z);
}
