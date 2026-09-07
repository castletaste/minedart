import 'package:flame_3d/components.dart';
import 'package:flame_3d/core.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('discard releases draws submitted before a traversal failure', () {
    final context = RenderContext3D(GraphicsDevice(backend: _FakeBackend()));
    final abandoned = _ProbeObject();
    context.submitDraw(abandoned, Matrix4.identity());

    context.discardPendingDraws();
    final nextFrame = _ProbeObject();
    context.submitDraw(nextFrame, Matrix4.identity());
    context.flush();

    expect(abandoned.draws, 0);
    expect(nextFrame.draws, 1);
  });

  test('failed flush releases submitted objects and resets the next frame', () {
    final context = RenderContext3D(GraphicsDevice(backend: _FakeBackend()));
    final initial = _ProbeObject();
    context.submitDraw(initial, Matrix4.identity());
    context.flush();
    expect(initial.draws, 1);
    expect(context.drawCount, 1);

    final failure = _ProbeObject(throwOnDraw: true);
    final skipped = _ProbeObject();
    context
      ..submitDraw(failure, Matrix4.identity())
      ..submitDraw(skipped, Matrix4.identity());

    expect(context.flush, throwsStateError);
    expect(failure.draws, 1);
    expect(skipped.draws, 0);
    expect(
      context.drawCount,
      1,
      reason: 'keep the last successful frame count',
    );

    final nextFrame = _ProbeObject();
    context.submitDraw(nextFrame, Matrix4.identity());
    context.flush();

    expect(failure.draws, 1, reason: 'failed entries must not be retried');
    expect(nextFrame.draws, 1);
    expect(context.drawCount, 1);
  });
}

final class _ProbeObject extends Object3D {
  _ProbeObject({this.throwOnDraw = false});

  final bool throwOnDraw;
  int draws = 0;

  @override
  void draw(RenderContext context) {
    draws++;
    if (throwOnDraw) throw StateError('synthetic draw failure');
  }
}

final class _FakeBackend extends GpuBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
