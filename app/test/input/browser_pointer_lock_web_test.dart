@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/input/browser_pointer_lock_web.dart';
import 'package:minedart/input/mouse_look.dart';
import 'package:web/web.dart' as web;

void main() {
  test('locked DOM listeners preserve look and emit one action per button', () {
    final bridge = BrowserPointerLock.forTesting(isLocked: () => true);
    addTearDown(bridge.dispose);
    final events = <MouseLookEvent>[];
    final subscription = bridge.events.listen(events.add);
    addTearDown(subscription.cancel);

    final movement = web.MouseEvent(
      'mousemove',
      web.MouseEventInit(movementX: 7, movementY: -5),
    );
    web.document.dispatchEvent(movement);

    final primary = web.PointerEvent(
      'pointerdown',
      web.PointerEventInit(button: 0, cancelable: true),
    );
    web.document.dispatchEvent(primary);

    final secondary = web.PointerEvent(
      'pointerdown',
      web.PointerEventInit(button: 2, cancelable: true),
    );
    web.document.dispatchEvent(secondary);
    final contextMenu = web.MouseEvent(
      'contextmenu',
      web.MouseEventInit(button: 2, cancelable: true),
    );
    web.document.dispatchEvent(contextMenu);

    expect(events, hasLength(3));
    expect(events[0], isA<MouseDelta>());
    final delta = events[0] as MouseDelta;
    expect(delta.dx, 7);
    expect(delta.dy, -5);
    expect(events[1], isA<MousePrimaryPressed>());
    expect(events[2], isA<MouseSecondaryPressed>());
    expect(primary.defaultPrevented, isTrue);
    expect(secondary.defaultPrevented, isTrue);
    expect(contextMenu.defaultPrevented, isTrue);
  });

  test('unlocked DOM listeners neither consume nor emit pointer actions', () {
    final bridge = BrowserPointerLock.forTesting(isLocked: () => false);
    addTearDown(bridge.dispose);
    final events = <MouseLookEvent>[];
    final subscription = bridge.events.listen(events.add);
    addTearDown(subscription.cancel);

    final primary = web.PointerEvent(
      'pointerdown',
      web.PointerEventInit(button: 0, cancelable: true),
    );
    web.document.dispatchEvent(primary);
    final contextMenu = web.MouseEvent(
      'contextmenu',
      web.MouseEventInit(button: 2, cancelable: true),
    );
    web.document.dispatchEvent(contextMenu);

    expect(events, isEmpty);
    expect(primary.defaultPrevented, isFalse);
    expect(contextMenu.defaultPrevented, isFalse);
  });

  test(
    'delayed contextmenu does not duplicate or suppress rapid clicks',
    () async {
      final bridge = BrowserPointerLock.forTesting(isLocked: () => true);
      addTearDown(bridge.dispose);
      final events = <MouseLookEvent>[];
      final subscription = bridge.events.listen(events.add);
      addTearDown(subscription.cancel);

      web.document.dispatchEvent(
        web.PointerEvent(
          'pointerdown',
          web.PointerEventInit(button: 2, cancelable: true),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final delayedMenu = web.MouseEvent(
        'contextmenu',
        web.MouseEventInit(button: 2, cancelable: true),
      );
      web.document.dispatchEvent(delayedMenu);
      web.document
        ..dispatchEvent(
          web.PointerEvent(
            'pointerdown',
            web.PointerEventInit(button: 2, cancelable: true),
          ),
        )
        ..dispatchEvent(
          web.PointerEvent(
            'pointerdown',
            web.PointerEventInit(button: 2, cancelable: true),
          ),
        );

      expect(events.whereType<MouseSecondaryPressed>(), hasLength(3));
      expect(delayedMenu.defaultPrevented, isTrue);
    },
  );

  test('release waits for pointer lock change acknowledgement', () async {
    var locked = true;
    final bridge = BrowserPointerLock.forTesting(isLocked: () => locked);
    addTearDown(bridge.dispose);

    final release = bridge.releaseAndWait();
    var completed = false;
    unawaited(release.whenComplete(() => completed = true));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    locked = false;
    web.document.dispatchEvent(web.Event('pointerlockchange'));
    await release;
    expect(completed, isTrue);
  });

  test('dispose terminates a pending release wait', () async {
    final bridge = BrowserPointerLock.forTesting(isLocked: () => true);

    final release = bridge.releaseAndWait();
    bridge.dispose();

    await expectLater(release, throwsA(isA<StateError>()));
  });
}
