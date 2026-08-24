import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

import 'mouse_look.dart';

/// Pointer Lock bridge for Chrome/Edge/Safari WebGPU builds.
final class BrowserPointerLock {
  BrowserPointerLock() {
    _mouseMoveListener = ((web.Event event) {
      if (!isLocked) return;
      final mouse = event as web.MouseEvent;
      _events.add(MouseDelta(mouse.movementX, mouse.movementY));
    }).toJS;
    _lockChangeListener = ((web.Event _) {
      final locked = isLocked;
      if (_lastLocked == locked) return;
      _lastLocked = locked;
      _events.add(MouseCaptureChanged(captured: locked));
    }).toJS;
    _lockErrorListener = ((web.Event _) {
      _lastLocked = false;
      _events.add(const MouseCaptureChanged(captured: false));
    }).toJS;
    _pointerDownListener = ((web.Event event) {
      try {
        if (!isLocked) return;
        final pointer = event as web.PointerEvent;
        if (pointer.button == 0) {
          event.preventDefault();
          _events.add(const MousePrimaryPressed());
        } else if (pointer.button == 2) {
          event.preventDefault();
          _emitSecondary();
        }
      } on Object catch (error, stackTrace) {
        debugPrint('Browser pointerdown failed: $error\n$stackTrace');
      }
    }).toJS;
    _contextMenuListener = ((web.Event event) {
      try {
        if (!isLocked) return;
        event.preventDefault();
        _emitSecondary();
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
  late final web.EventListener _mouseMoveListener;
  late final web.EventListener _lockChangeListener;
  late final web.EventListener _lockErrorListener;
  late final web.EventListener _pointerDownListener;
  late final web.EventListener _contextMenuListener;
  bool _lastLocked = false;
  int _lastSecondaryMicros = 0;

  bool get isLocked => web.document.pointerLockElement != null;
  Stream<MouseLookEvent> get events => _events.stream;

  void _emitSecondary() {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now - _lastSecondaryMicros < 150000) return;
    _lastSecondaryMicros = now;
    _events.add(const MouseSecondaryPressed());
  }

  Future<void> capture() async {
    if (isLocked) return;
    final target = web.document.body ?? web.document.documentElement;
    if (target == null) return;
    await target.requestPointerLock().toDart;
  }

  void release() {
    if (isLocked) web.document.exitPointerLock();
  }

  void dispose() {
    release();
    web.document
      ..removeEventListener('mousemove', _mouseMoveListener)
      ..removeEventListener('pointerdown', _pointerDownListener)
      ..removeEventListener('contextmenu', _contextMenuListener)
      ..removeEventListener('pointerlockchange', _lockChangeListener)
      ..removeEventListener('pointerlockerror', _lockErrorListener);
    _events.close();
  }
}
