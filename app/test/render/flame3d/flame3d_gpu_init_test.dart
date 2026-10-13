import 'package:flame_3d/graphics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/render/flame3d/flame3d_voxel_renderer.dart';
import 'package:minedart/render/voxel_renderer.dart';

void main() {
  test('maps every flame_3d GPU startup stage onto the port', () {
    final cause = StateError('private driver detail');
    expect(
      {
        for (final kind in GpuInitializationFailureKind.values)
          kind.name: rendererInitializationFailure(
            GpuInitializationException(kind, cause: cause),
          ),
      }.map((name, error) => MapEntry(name, (error.kind.name, error.cause))),
      {
        for (final kind in RendererInitializationFailureKind.values)
          kind.name: (kind.name, cause),
      },
    );
  });
}
