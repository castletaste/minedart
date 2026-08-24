import 'dart:typed_data';
import 'dart:ui';

import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('Shader retained uniform metadata', () {
    test(
      'idempotent partial writes keep revision and changed bytes bump once',
      () {
        final harness = _ShaderHarness();
        final shader = harness.shader;

        shader.setVector3('Block.items[1]', Vector3(1, 2, 3));
        final first = harness.bind();
        expect(first.revision, 1);

        shader.setVector3('Block.items[1]', Vector3(1, 2, 3));
        final identicalWrite = harness.bind();
        expect(identicalWrite.identity, same(first.identity));
        expect(identicalWrite.revision, first.revision);
        expect(identicalWrite.bytes, first.bytes);

        shader.setVector3('Block.items[1]', Vector3(1, 9, 3));
        final changedWrite = harness.bind();
        expect(changedWrite.identity, same(first.identity));
        expect(changedWrite.revision, first.revision + 1);
        expect(changedWrite.bytes, isNot(first.bytes));
      },
    );

    test('raw, matrix, vector, color, uint, and float use byte comparison', () {
      final harness = _ShaderHarness();
      final shader = harness.shader;
      var expectedRevision = 0;

      void expectSingleChange(void Function() setter) {
        setter();
        expectedRevision++;
        expect(harness.bind().revision, expectedRevision);
        setter();
        expect(harness.bind().revision, expectedRevision);
      }

      expectSingleChange(() => shader.setVector4('Block', Vector4(1, 2, 3, 4)));
      expectSingleChange(
        () =>
            shader.setMatrix4('Block.matrix', Matrix4.diagonal3Values(2, 3, 4)),
      );
      expectSingleChange(
        () => shader.setVector2('Block.vector', Vector2(5, 6)),
      );
      expectSingleChange(
        () => shader.setColor('Block.color', const Color(0xFF336699)),
      );
      expectSingleChange(() => shader.setUint('Block.uintValue', 0xAABBCCDD));
      expectSingleChange(() => shader.setFloat('Block.floatValue', 7.25));
    });

    test('createResource resets binding identity and revision', () {
      final harness = _ShaderHarness();
      final shader = harness.shader;

      shader.setFloat('Block.floatValue', 3.5);
      final beforeRecreate = harness.bind();
      expect(beforeRecreate.revision, 1);

      shader.recreateResource = true;
      shader.resource;
      shader.setFloat('Block.floatValue', 3.5);
      final afterRecreate = harness.bind();

      expect(afterRecreate.identity, isNot(same(beforeRecreate.identity)));
      expect(afterRecreate.revision, 1);
      expect(afterRecreate.bytes, beforeRecreate.bytes);
    });
  });
}

final class _ShaderHarness {
  _ShaderHarness()
    : backend = _FakeBackend(),
      shader = FragmentShader.fromAsset('fake', slots: ['Block']) {
    device = GraphicsDevice(backend: backend)
      ..begin()
      ..beginPass(const Size(1, 1));
    shader.resource;
  }

  final _FakeBackend backend;
  final FragmentShader shader;
  late final GraphicsDevice device;

  _UniformCall bind() {
    backend.pass.uniformCalls.clear();
    shader.bind(device);
    return backend.pass.uniformCalls.single;
  }
}

final class _FakeBackend extends GpuBackend {
  _FakeBackend();

  late _FakeRenderPass pass;

  @override
  GpuBuffer createBuffer({
    required GpuStorageMode storageMode,
    required int sizeInBytes,
  }) => _FakeBuffer();

  @override
  GpuPipeline createPipeline({
    required GpuShader vertexShader,
    required GpuShader fragmentShader,
  }) => _FakePipeline();

  @override
  GpuRenderTarget createRenderTarget({
    required int width,
    required int height,
    required Color clearValue,
  }) => _FakeRenderTarget();

  @override
  GpuTexture createTexture({
    required GpuStorageMode storageMode,
    required int width,
    required int height,
    required GpuPixelFormat format,
  }) => _FakeTexture();

  @override
  GpuShaderLibrary loadShaderLibrary(String assetName) => _FakeShaderLibrary();

  @override
  GpuFrame beginFrame() => _FakeFrame(this);
}

final class _FakeFrame implements GpuFrame {
  const _FakeFrame(this.backend);

  final _FakeBackend backend;

  @override
  GpuRenderPass beginRenderPass(
    GpuRenderTarget target, {
    required BlendState blend,
    required DepthStencilState depthStencil,
  }) => backend.pass = _FakeRenderPass();

  @override
  void end() {}
}

final class _FakeRenderPass implements GpuRenderPass {
  final List<_UniformCall> uniformCalls = [];

  @override
  void bindIndexBuffer(
    GpuBufferView view,
    GpuIndexType indexType,
    int indexCount,
  ) {}

  @override
  void bindPipeline(GpuPipeline pipeline, CullMode cullMode) {}

  @override
  void bindTexture(GpuUniformSlot slot, GpuTexture texture) {}

  @override
  void bindUniform(
    GpuUniformSlot slot,
    ByteData data, {
    Object? bindingIdentity,
    int bindingRevision = 0,
  }) {
    uniformCalls.add(
      _UniformCall(
        identity: bindingIdentity,
        revision: bindingRevision,
        bytes: Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      ),
    );
  }

  @override
  void bindVertexBuffer(GpuBufferView view, int vertexCount) {}

  @override
  void clearBindings() {}

  @override
  void draw() {}

  @override
  void submit() {}
}

final class _FakeShaderLibrary implements GpuShaderLibrary {
  @override
  GpuShader operator [](String entryPoint) => _FakeShader();
}

final class _FakeShader implements GpuShader {
  @override
  GpuUniformSlot getUniformSlot(String slot) => const _FakeUniformSlot();
}

final class _FakeUniformSlot implements GpuUniformSlot {
  const _FakeUniformSlot();

  static const _offsets = <String, int>{
    'items': 0,
    'vector': 16,
    'color': 32,
    'uintValue': 48,
    'floatValue': 52,
    'matrix': 64,
  };

  @override
  int? get sizeInBytes => 128;

  @override
  int? getMemberOffsetInBytes(String member) => _offsets[member];
}

final class _FakeBuffer implements GpuBuffer {
  @override
  void write(ByteData data, {int destinationOffsetInBytes = 0}) {}
}

final class _FakePipeline implements GpuPipeline {}

final class _FakeRenderTarget implements GpuRenderTarget {
  @override
  GpuTexture get colorTexture => _FakeTexture();
}

final class _FakeTexture implements GpuTexture {
  @override
  Image asImage() => throw UnsupportedError('Fake texture has no image.');

  @override
  void write(ByteData data) {}
}

final class _UniformCall {
  const _UniformCall({
    required this.identity,
    required this.revision,
    required this.bytes,
  });

  final Object? identity;
  final int revision;
  final Uint8List bytes;
}
