import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/input/game_input_service.dart';
import 'package:minedart/input/mouse_look.dart';

void main() {
  test(
    'routes events only to the active client after an explicit handoff',
    () async {
      final backend = _FakeBackend();
      final service = GameInputService(backend: backend);
      addTearDown(service.close);
      final firstEvents = <MouseLookEvent>[];
      final secondEvents = <MouseLookEvent>[];
      final first = service.createClient(firstEvents.add);
      final second = service.createClient(secondEvents.add);

      first
        ..activate()
        ..resume();
      backend.add(const MouseDelta(1, 2));
      expect(firstEvents, hasLength(1));

      await first.suspend();
      second
        ..activate()
        ..resume();
      backend.add(const MouseDelta(3, 4));

      expect(firstEvents, hasLength(1));
      expect(secondEvents, hasLength(1));
      expect(await first.capture(), isFalse);
      expect(backend.captureCalls, 0);
    },
  );

  test('starts capture synchronously inside the caller gesture', () async {
    final backend = _FakeBackend();
    final service = GameInputService(backend: backend);
    addTearDown(service.close);
    final client = service.createClient((_) {})
      ..activate()
      ..resume();
    final grant = Completer<bool>();
    backend.nextCapture = grant.future;

    final capture = client.capture();

    expect(backend.captureCalls, 1);
    grant.complete(true);
    expect(await capture, isTrue);
  });

  test('late capture grant is compensated after suspension', () async {
    final backend = _FakeBackend();
    final service = GameInputService(backend: backend);
    addTearDown(service.close);
    final client = service.createClient((_) {})
      ..activate()
      ..resume();
    final grant = Completer<bool>();
    backend.nextCapture = grant.future;

    final capture = client.capture();
    final suspension = client.suspend();
    expect(backend.releaseCalls, 1);
    grant.complete(true);

    expect(await capture, isFalse);
    await suspension;
    expect(backend.releaseCalls, 2);
  });

  test('failed release blocks resume until a successful retry', () async {
    final backend = _FakeBackend()..releaseFailures = 1;
    final service = GameInputService(backend: backend);
    addTearDown(service.close);
    final client = service.createClient((_) {})
      ..activate()
      ..resume();

    await expectLater(client.suspend(), throwsA(isA<InputReleaseException>()));
    expect(client.resume, throwsStateError);

    await client.suspend();
    expect(client.resume, returnsNormally);
  });

  test(
    'backend close still runs when event subscription cancel fails',
    () async {
      final backend = _FakeBackend(
        events: Stream<MouseLookEvent>.multi((events) {
          events.onCancel = () => throw StateError('cancel failed');
        }),
      );
      final service = GameInputService(backend: backend);

      await expectLater(service.close(), throwsA(isA<InputReleaseException>()));

      expect(backend.closeCalls, 1);
    },
  );
}

final class _FakeBackend implements PointerCaptureBackend {
  _FakeBackend({Stream<MouseLookEvent>? events}) : _eventsOverride = events;

  final Stream<MouseLookEvent>? _eventsOverride;
  final StreamController<MouseLookEvent> _events =
      StreamController<MouseLookEvent>.broadcast(sync: true);
  Future<bool>? nextCapture;
  int captureCalls = 0;
  int releaseCalls = 0;
  int releaseFailures = 0;
  int closeCalls = 0;
  bool started = false;
  bool captured = false;

  void add(MouseLookEvent event) => _events.add(event);

  @override
  Stream<MouseLookEvent> get events => _eventsOverride ?? _events.stream;

  @override
  bool get isCaptured => captured;

  @override
  void start() => started = true;

  @override
  Future<bool> capture() {
    captureCalls++;
    return nextCapture ?? Future<bool>.value(captured = true);
  }

  @override
  Future<void> release() async {
    releaseCalls++;
    if (releaseFailures > 0) {
      releaseFailures--;
      throw StateError('release failed');
    }
    captured = false;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    await _events.close();
  }
}
