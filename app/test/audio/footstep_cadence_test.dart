import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/audio/audio.dart';

void main() {
  group('FootstepCadence', () {
    test('emits after one Classic stride of grounded movement', () {
      final cadence = FootstepCadence();
      const stride = FootstepCadence.classicStrideBlocks;

      expect(
        cadence.update(horizontalDistance: stride - 0.1, grounded: true),
        isFalse,
      );
      expect(cadence.update(horizontalDistance: 0.1, grounded: true), isTrue);
      expect(
        cadence.update(horizontalDistance: stride - 0.01, grounded: true),
        isFalse,
      );
      expect(cadence.update(horizontalDistance: 0.01, grounded: true), isTrue);
    });

    test('airborne movement clears partial grounded distance', () {
      final cadence = FootstepCadence();
      const stride = FootstepCadence.classicStrideBlocks;

      expect(
        cadence.update(horizontalDistance: stride * 0.75, grounded: true),
        isFalse,
      );
      expect(cadence.update(horizontalDistance: 0.2, grounded: false), isFalse);
      expect(
        cadence.update(horizontalDistance: stride * 0.5, grounded: true),
        isFalse,
      );
    });

    test('a stalled frame emits at most one step and keeps only remainder', () {
      final cadence = FootstepCadence();
      const stride = FootstepCadence.classicStrideBlocks;

      expect(
        cadence.update(horizontalDistance: stride * 5, grounded: true),
        isTrue,
      );
      expect(
        cadence.update(horizontalDistance: stride - 0.01, grounded: true),
        isFalse,
      );
    });

    test('ignores invalid or non-positive displacement', () {
      final cadence = FootstepCadence();

      expect(cadence.update(horizontalDistance: 0, grounded: true), isFalse);
      expect(
        cadence.update(horizontalDistance: double.nan, grounded: true),
        isFalse,
      );
    });
  });
}
