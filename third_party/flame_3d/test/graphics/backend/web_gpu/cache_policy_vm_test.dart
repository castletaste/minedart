import 'package:flutter_test/flutter_test.dart';

import 'cache_policy_test_suite.dart';

void main() {
  test('production cache switch defaults on', () {
    const enabled = bool.fromEnvironment(
      'FLAME_3D_WEBGPU_BIND_CACHE',
      defaultValue: true,
    );
    expect(enabled, isTrue);
  });

  runWebGpuCachePolicyTests();
}
