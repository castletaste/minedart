import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/render/renderer_selection.dart';

const bool _hasRendererDefine = bool.hasEnvironment(kMinedartRendererDefine);

void main() {
  test('defaults to flame_3d', () {
    expect(kDefaultMinedartRenderer, 'flame_3d');
    expect(
      rendererFromValue(kDefaultMinedartRenderer),
      MinedartRenderer.flame3d,
    );
    if (!_hasRendererDefine) {
      expect(selectedRenderer, MinedartRenderer.flame3d);
      expect(kUsesFlutterScene, isFalse);
    }
  });

  test('accepts only the two renderer names', () {
    expect(rendererFromValue('flutter_scene'), MinedartRenderer.flutterScene);
    for (final value in ['', 'flame3d', 'flutterScene', 'webgl']) {
      expect(
        () => rendererFromValue(value),
        throwsA(isA<ArgumentError>()),
        reason: value,
      );
    }
  });

  test('the const switch agrees with the validated selection', () {
    if (kMinedartRendererValue case 'flame_3d' || 'flutter_scene') {
      expect(
        kUsesFlutterScene,
        selectedRenderer == MinedartRenderer.flutterScene,
      );
    } else {
      expect(() => selectedRenderer, throwsA(isA<ArgumentError>()));
    }
  });
}
