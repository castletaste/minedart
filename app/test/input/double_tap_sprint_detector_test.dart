import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/input/double_tap_sprint_detector.dart';

void main() {
  group('DoubleTapSprintDetector', () {
    test('second down inside the window sprints while forward is held', () {
      final detector = DoubleTapSprintDetector();

      detector.forwardDown(Duration.zero);
      expect(detector.isSprinting, isFalse);
      detector.forwardUp();
      detector.forwardDown(const Duration(milliseconds: 300));

      expect(detector.isSprinting, isTrue);
      detector.forwardUp();
      expect(detector.isSprinting, isFalse);
    });

    test('second down outside the window starts a new first tap', () {
      final detector = DoubleTapSprintDetector();

      detector.forwardDown(Duration.zero);
      detector.forwardUp();
      detector.forwardDown(const Duration(milliseconds: 301));

      expect(detector.isSprinting, isFalse);
      detector.forwardUp();
      detector.forwardDown(const Duration(milliseconds: 500));
      expect(detector.isSprinting, isTrue);
    });

    test('repeat and duplicate down events cannot trigger sprint', () {
      final detector = DoubleTapSprintDetector();

      detector.forwardDown(Duration.zero);
      detector.forwardDown(const Duration(milliseconds: 40), isRepeat: true);
      detector.forwardDown(const Duration(milliseconds: 80));

      expect(detector.isSprinting, isFalse);
    });

    test('reset clears active sprint and an armed first tap', () {
      final detector = DoubleTapSprintDetector();

      detector.forwardDown(Duration.zero);
      detector.forwardUp();
      detector.reset();
      detector.forwardDown(const Duration(milliseconds: 100));
      expect(detector.isSprinting, isFalse);

      detector.forwardUp();
      detector.forwardDown(const Duration(milliseconds: 200));
      expect(detector.isSprinting, isTrue);
      detector.reset();
      expect(detector.isSprinting, isFalse);

      detector.forwardDown(const Duration(milliseconds: 250));
      expect(detector.isSprinting, isFalse);
    });

    test('backward timestamps never complete a double tap', () {
      final detector = DoubleTapSprintDetector();

      detector.forwardDown(const Duration(milliseconds: 200));
      detector.forwardUp();
      detector.forwardDown(const Duration(milliseconds: 100));

      expect(detector.isSprinting, isFalse);
    });
  });
}
