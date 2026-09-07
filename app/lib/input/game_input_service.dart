import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'browser_pointer_lock.dart';
import 'mouse_look.dart';

/// The application owns one platform channel. Games only own a routed client.
abstract interface class PointerCaptureBackend {
  Stream<MouseLookEvent> get events;
  bool get isCaptured;
  void start();
  Future<bool> capture();
  Future<void> release();
  Future<void> close();
}

final class InputReleaseException implements Exception {
  InputReleaseException(Iterable<Object> errors)
    : errors = List.unmodifiable(errors);

  final List<Object> errors;

  @override
  String toString() => 'Could not release input: ${errors.join('; ')}';
}

final class GameInputService {
  GameInputService({PointerCaptureBackend? backend})
    : _backend = backend ?? _PlatformPointerCapture() {
    _subscription = _backend.events.listen(
      (event) {
        if (!_closed && (!_suspended || event is MouseCaptureChanged)) {
          _client?._onEvent(event);
        }
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('Mouse input failed: $error\n$stack');
      },
    );
    _backend.start();
  }

  final PointerCaptureBackend _backend;
  late final StreamSubscription<MouseLookEvent> _subscription;
  GameInputClient? _client;
  Future<bool>? _capture;
  Future<void>? _suspending;
  Future<void>? _closing;
  int _generation = 0;
  bool _suspended = true;
  bool _released = true;
  bool _closed = false;

  GameInputClient createClient(void Function(MouseLookEvent) onEvent) =>
      GameInputClient._(this, onEvent);

  void _activate(GameInputClient client) {
    if (_closed || client._disposed) throw StateError('Input is closed');
    if (!_suspended || !_released || _suspending != null) {
      if (identical(client, _client) && !_suspended) return;
      throw StateError('Release input before changing its owner');
    }
    _client = client;
    _generation++;
  }

  void _resume(GameInputClient client) {
    if (_closed || client._disposed || !identical(client, _client)) return;
    if (!_released || _suspending != null) {
      throw StateError('Input release has not completed');
    }
    _suspended = false;
  }

  Future<bool> _request(GameInputClient client) {
    if (_closed ||
        _suspended ||
        client._disposed ||
        !identical(_client, client)) {
      return Future.value(false);
    }
    if (_capture case final pending?) return pending;
    final generation = _generation;
    // Do not defer this call: browsers require the original user gesture.
    final Future<bool> request;
    try {
      request = _backend.capture();
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    return _capture = _completeCapture(request, generation);
  }

  Future<bool> _completeCapture(Future<bool> request, int generation) async {
    try {
      final captured = await request;
      if (_closed || _suspended || generation != _generation) {
        if (captured) {
          try {
            await _backend.release();
          } catch (error) {
            _released = false;
            throw InputReleaseException([error]);
          }
        }
        return false;
      }
      return captured;
    } finally {
      _capture = null;
    }
  }

  /// Invalidates capture immediately, then waits for a late grant and release.
  Future<void> suspend() {
    if (_suspending case final pending?) return pending;
    _suspended = true;
    _released = false;
    _generation++;
    final capture = _capture;
    return _suspending = _releaseAndDrain(capture);
  }

  Future<void> _releaseAndDrain(Future<bool>? capture) async {
    final errors = <Object>[];
    try {
      try {
        await _backend.release();
      } catch (error) {
        errors.add(error);
      }
      try {
        await capture;
      } on InputReleaseException catch (error) {
        errors.addAll(error.errors);
      } catch (_) {
        // A rejected capture acquired no platform resource.
      }
      _released = errors.isEmpty;
      if (errors.isNotEmpty) throw InputReleaseException(errors);
    } finally {
      _suspending = null;
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    final errors = <Object>[];
    try {
      await suspend();
    } catch (error) {
      errors.add(error);
    }
    _client = null;
    try {
      await _subscription.cancel();
    } catch (error) {
      errors.add(error);
    }
    try {
      await _backend.close();
    } catch (error) {
      errors.add(error);
    }
    if (errors.isNotEmpty) throw InputReleaseException(errors);
  }
}

/// A stale game cannot capture or disconnect the active game's platform input.
final class GameInputClient {
  GameInputClient._(this._owner, this._onEvent);

  final GameInputService _owner;
  final void Function(MouseLookEvent) _onEvent;
  bool _disposed = false;

  bool get isActive => !_disposed && identical(_owner._client, this);
  bool get isCaptured =>
      isActive && !_owner._suspended && _owner._backend.isCaptured;

  void activate() => _owner._activate(this);
  void resume() => _owner._resume(this);
  Future<bool> capture() => _owner._request(this);
  Future<void> suspend() => isActive ? _owner.suspend() : Future.value();

  void dispose() {
    _disposed = true;
    if (identical(_owner._client, this)) _owner._client = null;
  }
}

final class _PlatformPointerCapture implements PointerCaptureBackend {
  final MouseLook? _native = kIsWeb ? null : MouseLook();
  final BrowserPointerLock? _browser = kIsWeb ? BrowserPointerLock() : null;

  @override
  Stream<MouseLookEvent> get events => _native?.events ?? _browser!.events;
  @override
  bool get isCaptured => _native?.isCaptured ?? _browser!.isLocked;
  @override
  void start() => _native?.start();
  @override
  Future<bool> capture() async {
    if (_native case final native?) return native.capture();
    await _browser!.capture();
    return _browser.isLocked;
  }

  @override
  Future<void> release() async {
    if (_native case final native?) {
      try {
        await native.release();
      } on MissingPluginException {
        // Platforms without the native bridge have no cursor to release.
      }
    } else {
      await _browser!.releaseAndWait();
    }
  }

  @override
  Future<void> close() async {
    if (_native case final native?) {
      await native.close();
    } else {
      _browser!.dispose();
    }
  }
}
