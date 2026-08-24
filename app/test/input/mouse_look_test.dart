import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/input/mouse_look.dart';

void main() {
  test('parses native mouse delta', () {
    final event = MouseLookEvent.fromPlatform(<String, Object>{
      'type': 'delta',
      'dx': 12,
      'dy': -4.5,
    });

    expect(event, isA<MouseDelta>());
    final delta = event! as MouseDelta;
    expect(delta.dx, 12);
    expect(delta.dy, -4.5);
  });

  test('parses native focus-loss release', () {
    final event = MouseLookEvent.fromPlatform(<String, Object>{
      'type': 'capture',
      'captured': false,
      'reason': 'window-focus-lost',
    });

    expect(event, isA<MouseCaptureChanged>());
    final capture = event! as MouseCaptureChanged;
    expect(capture.captured, isFalse);
    expect(capture.reason, 'window-focus-lost');
  });

  test('parses native window click capture request', () {
    final event = MouseLookEvent.fromPlatform(<String, Object>{
      'type': 'click',
    });

    expect(event, isA<MouseCaptureRequested>());
  });

  test('ignores malformed and unknown events', () {
    expect(MouseLookEvent.fromPlatform(null), isNull);
    expect(MouseLookEvent.fromPlatform({'type': 'other'}), isNull);
  });
}
