import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/render/target_outline.dart';

void main() {
  group('TargetOutline', () {
    test('builds one packed retained mesh', () {
      final outline = TargetOutline();

      expect(outline.mesh.surfaceCount, 1);
      expect(outline.surface.vertexCount, 12 * 8);
      expect(outline.surface.indexCount, 12 * 36);
      expect(outline.meshAllocationCount, 1);
      expect(outline.hasTarget, isFalse);
    });

    test('target updates only mutate transform and preserve mesh identity', () {
      final outline = TargetOutline();
      final mesh = outline.mesh;
      final surface = outline.surface;

      for (var i = 0; i < 100; i++) {
        outline.showAt(i, i % 64, 100 - i);
      }

      expect(identical(outline.mesh, mesh), isTrue);
      expect(identical(outline.surface, surface), isTrue);
      expect(outline.targetX, 99);
      expect(outline.targetY, 35);
      expect(outline.targetZ, 1);
      expect(outline.position.x, 99);
      expect(outline.position.y, 35);
      expect(outline.position.z, 1);
      expect(outline.isShown, isTrue);

      outline.hide();
      expect(outline.isShown, isFalse);
      outline.showAt(1, 2, 3);
      outline.enabled = false;
      expect(outline.hasTarget, isTrue);
      expect(outline.isShown, isFalse);
    });

    test('high contrast mutates retained material state only', () {
      final outline = TargetOutline();
      final mesh = outline.mesh;

      outline
        ..setHighContrast(true)
        ..setHighContrast(false);

      expect(outline.highContrast, isFalse);
      expect(identical(outline.mesh, mesh), isTrue);
      expect(outline.meshAllocationCount, 1);
    });
  });
}
