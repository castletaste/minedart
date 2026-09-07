import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:web/web.dart' as web;

import 'mouse_look.dart';

/// Pointer Lock bridge for Chrome/Edge/Safari WebGPU builds.
final class BrowserPointerLock {
  BrowserPointerLock() : this._(null);

  @visibleForTesting
  BrowserPointerLock.forTesting({required bool Function() isLocked})
    : this._(isLocked);

  BrowserPointerLock._(this._isLockedOverride) {
    _mouseMoveListener = ((web.Event event) {
      if (_disposed || !isLocked) return;
      final mouse = event as web.MouseEvent;
      _events.add(MouseDelta(mouse.movementX, mouse.movementY));
    }).toJS;
    _lockChangeListener = ((web.Event _) {
      if (_disposed) return;
      final locked = isLocked;
      if (!locked) {
        _released?.complete();
        _released = null;
      }
      if (_lastLocked == locked) return;
      _lastLocked = locked;
      _events.add(MouseCaptureChanged(captured: locked));
    }).toJS;
    _lockErrorListener = ((web.Event _) {
      if (_disposed) return;
      _lastLocked = false;
      _events.add(const MouseCaptureChanged(captured: false));
    }).toJS;
    _pointerDownListener = ((web.Event event) {
      try {
        if (_disposed || !isLocked) return;
        final pointer = event as web.PointerEvent;
        if (pointer.pointerType != 'mouse') return;
        if (pointer.button == 0) {
          event.preventDefault();
          _events.add(const MousePrimaryPressed());
        } else if (pointer.button == 2) {
          event.preventDefault();
          _events.add(const MouseSecondaryPressed());
        }
      } on Object catch (error, stackTrace) {
        debugPrint('Browser pointerdown failed: $error\n$stackTrace');
      }
    }).toJS;
    _contextMenuListener = ((web.Event event) {
      try {
        if (_disposed || !isLocked) return;
        event.preventDefault();
        // Pointerdown owns the action. Contextmenu may arrive much later and
        // must neither duplicate it nor suppress a distinct rapid click.
      } on Object catch (error, stackTrace) {
        debugPrint('Browser contextmenu failed: $error\n$stackTrace');
      }
    }).toJS;

    web.document
      ..addEventListener('mousemove', _mouseMoveListener)
      ..addEventListener('pointerdown', _pointerDownListener)
      ..addEventListener('contextmenu', _contextMenuListener)
      ..addEventListener('pointerlockchange', _lockChangeListener)
      ..addEventListener('pointerlockerror', _lockErrorListener);
  }

  final _events = StreamController<MouseLookEvent>.broadcast(sync: true);
  final bool Function()? _isLockedOverride;
  late final web.EventListener _mouseMoveListener;
  late final web.EventListener _lockChangeListener;
  late final web.EventListener _lockErrorListener;
  late final web.EventListener _pointerDownListener;
  late final web.EventListener _contextMenuListener;
  bool _lastLocked = false;
  bool _disposed = false;
  Completer<void>? _released;

  bool get isLocked =>
      _isLockedOverride?.call() ?? web.document.pointerLockElement != null;
  Stream<MouseLookEvent> get events => _events.stream;

  Future<void> capture() async {
    if (_disposed || isLocked) return;
    final target = web.document.body ?? web.document.documentElement;
    if (target == null) return;
    await target.requestPointerLock().toDart;
    if (_disposed) release();
  }

  void release() {
    if (isLocked) web.document.exitPointerLock();
  }

  Future<void> releaseAndWait() async {
    if (!isLocked) return;
    final released = _released ??= Completer<void>();
    release();
    await released.future.timeout(const Duration(seconds: 5));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    release();
    final released = _released;
    if (released != null && !released.isCompleted) {
      released.completeError(
        StateError('Pointer lock disposed during release'),
      );
    }
    _released = null;
    web.document
      ..removeEventListener('mousemove', _mouseMoveListener)
      ..removeEventListener('pointerdown', _pointerDownListener)
      ..removeEventListener('contextmenu', _contextMenuListener)
      ..removeEventListener('pointerlockchange', _lockChangeListener)
      ..removeEventListener('pointerlockerror', _lockErrorListener);
    _events.close();
  }
}
