@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/input/touch_capabilities.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('native mobile platforms prefer touch controls', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(prefersTouchControls, isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(prefersTouchControls, isTrue);
  });

  test('desktop platforms do not default to touch controls', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(prefersTouchControls, isFalse);
  });
}
