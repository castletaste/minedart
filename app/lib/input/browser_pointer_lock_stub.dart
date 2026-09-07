import 'dart:async';

import 'mouse_look.dart';

final class BrowserPointerLock {
  const BrowserPointerLock();

  bool get isLocked => false;
  Stream<MouseLookEvent> get events => const Stream<MouseLookEvent>.empty();

  Future<void> capture() async {}
  void release() {}
  Future<void> releaseAndWait() async {}
  void dispose() {}
}
