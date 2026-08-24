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
      'click' => const MouseCaptureRequested(),
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

/// A click reached the macOS game window while the mouse was not captured.
final class MouseCaptureRequested extends MouseLookEvent {
  const MouseCaptureRequested();
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
  MouseLook({MethodChannel? methods, EventChannel? nativeEvents})
    : _methods = methods ?? const MethodChannel('minedart/mouse'),
      _nativeEvents =
          nativeEvents ?? const EventChannel('minedart/mouse/events');

  final MethodChannel _methods;
  final EventChannel _nativeEvents;
  final StreamController<MouseLookEvent> _events =
      StreamController<MouseLookEvent>.broadcast(sync: true);

  StreamSubscription<Object?>? _nativeSubscription;
  bool _started = false;
  bool _closed = false;
  bool _captured = false;

  Stream<MouseLookEvent> get events => _events.stream;
  bool get isCaptured => _captured;

  void start() {
    if (_started || _closed) return;
    _started = true;
    _nativeSubscription = _nativeEvents.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: _events.addError,
    );
  }

  Future<bool> capture() async {
    final result = await _methods.invokeMapMethod<String, Object?>('capture');
    final captured = result?['captured'] == true;
    _setCaptured(captured);
    return captured;
  }

  Future<void> release() async {
    await _methods.invokeMethod<void>('release');
    _setCaptured(false);
  }

  Future<void> close() async {
    if (_closed) return;
    if (_captured) {
      try {
        await release();
      } on PlatformException {
        // Native window teardown also restores the cursor association.
      } on MissingPluginException {
        // Non-macOS targets do not install the native bridge.
      }
    }
    _closed = true;
    await _nativeSubscription?.cancel();
    await _events.close();
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
