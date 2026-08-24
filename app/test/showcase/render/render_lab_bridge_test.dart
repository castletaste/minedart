import 'package:flame_3d/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/render/block_particle_pool.dart';
import 'package:minedart/showcase/render/render_lab_bridge.dart';
import 'package:minedart/showcase/render/render_settings.dart';
import 'package:minedart/showcase/render/target_outline.dart';

final class _FogTarget implements FogUniformTarget {
  FogPreset? preset;

  @override
  void applyFog(FogPreset preset) {
    this.preset = preset;
  }
}

void main() {
  group('RenderLabBridge', () {
    test('dispatches typed settings into retained targets', () {
      final fog = _FogTarget();
      final outline = TargetOutline()..showAt(1, 2, 3);
      final particles = BlockParticlePool(capacity: 2);
      final camera = CameraComponent3D(fovY: 60);
      final bridge = RenderLabBridge(
        capabilities: RenderCapabilities.native,
        fogTarget: fog,
        targetOutline: outline,
        particlePool: particles,
        camera: camera,
      );
      addTearDown(bridge.dispose);
      final mesh = outline.mesh;

      expect(fog.preset, FogPreset.far);
      expect(
        bridge.dispatch(const SetFogPreset(FogPreset.normal)).changed,
        isTrue,
      );
      expect(fog.preset, FogPreset.normal);
      expect(
        bridge.dispatch(const SetFogPreset(FogPreset.normal)).status,
        RenderLabUpdateStatus.unchanged,
      );
      bridge
        ..dispatch(const SetTargetOutlineEnabled(false))
        ..dispatch(const SetReducedMotion(true))
        ..dispatch(const SetHighContrast(true))
        ..dispatch(const SetFieldOfView(88));

      expect(outline.enabled, isFalse);
      expect(outline.highContrast, isTrue);
      expect(identical(outline.mesh, mesh), isTrue);
      expect(particles.reducedMotion, isTrue);
      expect(camera.fovY, 88);
    });

    test('reports unsupported changes instead of widening capabilities', () {
      final fog = _FogTarget();
      final bridge = RenderLabBridge(
        capabilities: const RenderCapabilities(fog: false),
        fogTarget: fog,
      );
      addTearDown(bridge.dispose);

      expect(bridge.settings.fogPreset, FogPreset.off);
      expect(fog.preset, FogPreset.off);
      final result = bridge.setFogPreset(FogPreset.near);
      expect(result.status, RenderLabUpdateStatus.unsupported);
      expect(result.unsupportedCapability, RenderCapability.fog);
      expect(bridge.settings.fogPreset, FogPreset.off);
    });
  });
}
