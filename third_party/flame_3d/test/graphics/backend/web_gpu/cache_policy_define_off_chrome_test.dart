@TestOn('browser')
library;

import 'package:flame_3d/src/graphics/backend/gpu_backend.dart';
import 'package:flame_3d/src/graphics/backend/web_gpu/cache_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compile-time cache-off release arm is selectable', () {
    expect(GpuBackend.initialize, isNotNull);
    expect(webGpuBindCacheEnabled, isFalse);
  });
}
