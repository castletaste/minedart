import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/input/mouse_look.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('ignores malformed and unknown events', () {
    expect(MouseLookEvent.fromPlatform(null), isNull);
    expect(MouseLookEvent.fromPlatform({'type': 'click'}), isNull);
    expect(MouseLookEvent.fromPlatform({'type': 'other'}), isNull);
  });

  test('close compensates a late capture grant and is idempotent', () async {
    const methods = MethodChannel('test/mouse-look-pending');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final grant = Completer<Map<String, Object?>>();
    var captureCalls = 0;
    var releaseCalls = 0;
    messenger.setMockMethodCallHandler(methods, (call) async {
      switch (call.method) {
        case 'capture':
          captureCalls++;
          return grant.future;
        case 'release':
          releaseCalls++;
          return null;
      }
      throw StateError('Unexpected method ${call.method}');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(methods, null));
    final mouse = MouseLook(methods: methods);

    final capture = mouse.capture();
    final firstClose = mouse.close();
    final secondClose = mouse.close();
    expect(identical(firstClose, secondClose), isTrue);
    grant.complete(<String, Object?>{'captured': true});

    expect(await capture, isFalse);
    await firstClose;
    expect(captureCalls, 1);
    expect(releaseCalls, 2);
    expect(mouse.isCaptured, isFalse);
    expect(await mouse.capture(), isFalse);
    expect(captureCalls, 1);
  });

  test('close closes public events even when native cancel fails', () async {
    const methods = MethodChannel('test/mouse-look-close-methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async => null);
    final nativeEvents = StreamController<Object?>(
      onCancel: () => throw StateError('cancel failed'),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(methods, null);
    });
    final mouse = MouseLook(
      methods: methods,
      nativeEventStream: nativeEvents.stream,
    );
    final done = Completer<void>();
    mouse.events.listen((_) {}, onDone: done.complete);
    mouse.start();
    await Future<void>.delayed(Duration.zero);

    await expectLater(mouse.close(), throwsA(isA<StateError>()));
    await done.future;
  });

  test('a paused event listener cannot block close', () async {
    const methods = MethodChannel('test/mouse-look-paused-listener');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(methods, null));
    final mouse = MouseLook(methods: methods);
    final subscription = mouse.events.listen((_) {})..pause();
    addTearDown(subscription.cancel);

    await mouse.close().timeout(const Duration(milliseconds: 100));
  });
}
