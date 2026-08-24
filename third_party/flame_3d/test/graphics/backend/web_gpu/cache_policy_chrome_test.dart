@TestOn('browser')
library;

import 'package:flame_3d/src/graphics/backend/gpu_backend.dart';
import 'package:flame_3d/src/graphics/backend/web_gpu/cache_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cache_policy_test_suite.dart';

void main() {
  test('conditional WebGPU backend and default cache arm compile', () {
    expect(GpuBackend.initialize, isNotNull);
    expect(webGpuBindCacheEnabled, isTrue);
  });

  runWebGpuCachePolicyTests();
}
