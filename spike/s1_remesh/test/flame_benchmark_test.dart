import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame_3d/graphics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:s1_remesh/src/chunk_mesher.dart';
import 'package:s1_remesh/src/flame_benchmark.dart';

void main() {
  test('benchmark geometry is deterministic and in requested quad range', () {
    final mesh = meshChunk(makeBenchmarkChunk());
    expect(mesh.quadCount, inInclusiveRange(2000, 4000));
    expect(mesh.vertexCount, mesh.quadCount * 4);
    expect(mesh.indexCount, mesh.quadCount * 6);
    expect(mesh.indices.reduce((a, b) => a > b ? a : b), lessThan(65536));
  });

  test('packed surface exposes render-compatible geometry contract', () {
    final data = meshChunk(makeBenchmarkChunk());
    final surface = PackedSurface(data);
    expect(surface.verticesBytes, data.vertices.lengthInBytes);
    expect(surface.indicesBytes, data.indices.lengthInBytes);
    expect(surface.vertexCount, data.vertexCount);
    expect(surface.indexCount, data.indexCount);
    expect(surface.positions.length, data.vertexCount * 3);
    expect(surface.indices, orderedEquals(data.indices));
    expect(surface.aabb.min.x, 0);
    expect(surface.aabb.max.x, 16);
  });

  test('packed surface uploads full packed buffers at the correct offsets', () {
    final backend = RecordingGpuBackend();
    final data = meshChunk(makeBenchmarkChunk());
    final surface = PackedSurface(data);
    surface.resource;

    expect(
      backend.buffer!.sizeInBytes,
      data.vertices.lengthInBytes + data.indices.lengthInBytes,
    );
    expect(backend.buffer!.writes, [
      (offset: 0, length: data.vertices.lengthInBytes),
      (offset: data.vertices.lengthInBytes, length: data.indices.lengthInBytes),
    ]);
  });

  test(
    'run exact flame_3d benchmark (JIT)',
    () {
      final result = runFlameBenchmark();
      print('S1_FLAME_JIT_BEGIN');
      print(const JsonEncoder.withIndent('  ').convert(result));
      print('S1_FLAME_JIT_END');
      expect(result['iterations'], 100);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

final class RecordingGpuBackend extends GpuBackend {
  RecordingGpuBuffer? buffer;

  @override
  GpuBuffer createBuffer({
    required GpuStorageMode storageMode,
    required int sizeInBytes,
  }) => buffer = RecordingGpuBuffer(sizeInBytes);

  @override
  GpuFrame beginFrame() => throw UnimplementedError();
  @override
  GpuPipeline createPipeline({
    required GpuShader vertexShader,
    required GpuShader fragmentShader,
  }) => throw UnimplementedError();
  @override
  GpuRenderTarget createRenderTarget({
    required int width,
    required int height,
    required Color clearValue,
  }) => throw UnimplementedError();
  @override
  GpuTexture createTexture({
    required GpuStorageMode storageMode,
    required int width,
    required int height,
    required GpuPixelFormat format,
  }) => throw UnimplementedError();
  @override
  GpuShaderLibrary loadShaderLibrary(String assetName) =>
      throw UnimplementedError();
}

final class RecordingGpuBuffer implements GpuBuffer {
  RecordingGpuBuffer(this.sizeInBytes);

  final int sizeInBytes;
  final writes = <({int offset, int length})>[];

  @override
  void write(ByteData data, {int destinationOffsetInBytes = 0}) {
    writes.add((offset: destinationOffsetInBytes, length: data.lengthInBytes));
  }
}
