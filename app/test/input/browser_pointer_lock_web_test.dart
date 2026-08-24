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
}
