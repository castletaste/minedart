import 'dart:async';

import 'package:flutter/services.dart';

sealed class MouseLookEvent {
  const MouseLookEvent();

  static MouseLookEvent? fromPlatform(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    return switch (value['type']) {
      'delta' => MouseDelta(
        (value['dx'] as num?)?.toDouble() ?? 0,
        (value['dy'] as num?)?.toDouble() ?? 0,
      ),
      'capture' => MouseCaptureChanged(
        captured: value['captured'] == true,
        reason: value['reason'] as String?,
      ),
      _ => null,
    };
  }
}

final class MouseDelta extends MouseLookEvent {
  const MouseDelta(this.dx, this.dy);

  final double dx;
  final double dy;
}

final class MouseCaptureChanged extends MouseLookEvent {
  const MouseCaptureChanged({required this.captured, this.reason});

  final bool captured;
  final String? reason;
}

/// Primary press delivered by the browser Pointer Lock bridge.
final class MousePrimaryPressed extends MouseLookEvent {
  const MousePrimaryPressed();
}

/// Secondary press delivered by the browser Pointer Lock bridge.
final class MouseSecondaryPressed extends MouseLookEvent {
  const MouseSecondaryPressed();
}

/// Typed wrapper around the macOS relative-mouse platform channels.
final class MouseLook {
  MouseLook({
    MethodChannel? methods,
    EventChannel? nativeEvents,
    Stream<Object?>? nativeEventStream,
  }) : _methods = methods ?? const MethodChannel('minedart/mouse'),
       _nativeEvents =
           nativeEventStream ??
           (nativeEvents ?? const EventChannel('minedart/mouse/events'))
               .receiveBroadcastStream();

  final MethodChannel _methods;
  final Stream<Object?> _nativeEvents;
  final StreamController<MouseLookEvent> _events =
      StreamController<MouseLookEvent>.broadcast(sync: true);

  StreamSubscription<Object?>? _nativeSubscription;
  Future<bool>? _capture;
  Future<void>? _closing;
  int _captureGeneration = 0;
  bool _started = false;
  bool _closed = false;
  bool _captured = false;

  Stream<MouseLookEvent> get events => _events.stream;
  bool get isCaptured => _captured;

  void start() {
    if (_started || _closed) return;
    _started = true;
    _nativeSubscription = _nativeEvents.listen(
      _handleNativeEvent,
      onError: _events.addError,
    );
  }

  Future<bool> capture() {
    if (_closed) return Future<bool>.value(false);
    if (_capture case final pending?) return pending;
    final generation = _captureGeneration;
    final Future<Map<String, Object?>?> request;
    try {
      request = _methods.invokeMapMethod<String, Object?>('capture');
    } catch (error, stack) {
      return Future<bool>.error(error, stack);
    }
    return _capture = _completeCapture(request, generation);
  }

  Future<bool> _completeCapture(
    Future<Map<String, Object?>?> request,
    int generation,
  ) async {
    try {
      final result = await request;
      final captured = result?['captured'] == true;
      if (_closed || generation != _captureGeneration) {
        if (captured) await _releaseNative();
        return false;
      }
      _setCaptured(captured);
      return captured;
    } finally {
      _capture = null;
    }
  }

  Future<void> release() {
    if (_closed) return Future<void>.value();
    _captureGeneration++;
    return _releaseAndUpdate();
  }

  Future<void> _releaseAndUpdate() async {
    await _releaseNative();
    _setCaptured(false);
  }

  Future<void> _releaseNative() => _methods.invokeMethod<void>('release');

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _captureGeneration++;
    final pendingCapture = _capture;
    final failures = <({Object error, StackTrace stack})>[];

    Future<void> attempt(Future<void> Function() operation) async {
      try {
        await operation();
      } on MissingPluginException {
        // Platforms without the native bridge own no cursor or event port.
      } catch (error, stack) {
        failures.add((error: error, stack: stack));
      }
    }

    await attempt(_releaseNative);
    if (pendingCapture != null) {
      await attempt(() async {
        await pendingCapture;
      });
    }
    _captured = false;
    await attempt(() async {
      await _nativeSubscription?.cancel();
    });
    unawaited(_events.close());

    if (failures.isNotEmpty) {
      final first = failures.first;
      Error.throwWithStackTrace(first.error, first.stack);
    }
  }

  void _handleNativeEvent(Object? rawEvent) {
    final event = MouseLookEvent.fromPlatform(rawEvent);
    if (event == null || _closed) return;
    if (event case MouseCaptureChanged(:final captured)) {
      _captured = captured;
    }
    _events.add(event);
  }

  void _setCaptured(bool captured) {
    if (_captured == captured || _closed) return;
    _captured = captured;
    _events.add(MouseCaptureChanged(captured: captured));
  }
}
