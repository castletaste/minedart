import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/render/render_settings.dart';
import 'package:minedart_core/minedart_core.dart' show WorldDims;

void main() {
  group('FogPreset', () {
    test('cycles deterministically through every preset', () {
      var preset = FogPreset.near;
      final seen = <FogPreset>[];
      for (var i = 0; i < FogPreset.values.length; i++) {
        seen.add(preset);
        preset = preset.next;
      }

      expect(seen, FogPreset.values);
      expect(preset, FogPreset.near);
      expect(FogPreset.classic, FogPreset.far);
      expect(FogPreset.normal.label, 'Normal');
      expect(FogPreset.far.fogStart, lessThan(FogPreset.far.fogEnd));
      expect(FogPreset.off.enabled, isFalse);
      expect(
        FogPreset.values.map((preset) => preset.renderDistanceChunks),
        <int>[3, 6, 10, WorldDims.worldChunksX],
      );
    });
  });

  group('RenderSettings capabilities', () {
    test('declares only live renderer features', () {
      expect(RenderCapability.values, <RenderCapability>[
        RenderCapability.fog,
        RenderCapability.targetOutline,
        RenderCapability.blockParticles,
        RenderCapability.frameMetrics,
        RenderCapability.minimap,
        RenderCapability.fieldOfView,
        RenderCapability.highContrast,
      ]);
    });

    test('web preserves WGSL fog and other live preferences', () {
      const requested = RenderSettings(
        fogPreset: FogPreset.near,
        highContrast: true,
        frameGraphEnabled: true,
        fieldOfViewDegrees: 82,
      );

      final resolved = requested.resolvedFor(RenderCapabilities.web);

      expect(resolved.fogPreset, FogPreset.near);
      expect(resolved.highContrast, isTrue);
      expect(resolved.frameGraphEnabled, isTrue);
      expect(resolved.fieldOfViewDegrees, 82);
      expect(RenderCapabilities.web.supports(RenderCapability.fog), isTrue);
    });

    test('unsupported features are never advertised as active', () {
      final resolved = const RenderSettings(
        targetOutlineEnabled: true,
        particlesEnabled: true,
        highContrast: true,
        frameGraphEnabled: true,
        fieldOfViewDegrees: 90,
      ).resolvedFor(RenderCapabilities.none);

      expect(resolved.fogPreset, FogPreset.off);
      expect(resolved.targetOutlineEnabled, isFalse);
      expect(resolved.particlesEnabled, isFalse);
      expect(resolved.highContrast, isFalse);
      expect(resolved.frameGraphEnabled, isFalse);
      expect(
        resolved.fieldOfViewDegrees,
        RenderSettings.defaults.fieldOfViewDegrees,
      );
    });

    test(
      'reduced motion suppresses but does not erase particle preference',
      () {
        const settings = RenderSettings(
          particlesEnabled: true,
          reducedMotion: true,
        );

        expect(settings.particlesEnabled, isTrue);
        expect(settings.particlesActive, isFalse);
        expect(settings.copyWith(reducedMotion: false).particlesActive, isTrue);
      },
    );
  });
}
