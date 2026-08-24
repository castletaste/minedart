import 'package:flame_3d/src/graphics/backend/gpu_bind_cache_counters.dart';
import 'package:meta/meta.dart';

/// Production WebGPU bind-cache switch.
///
/// Benchmark the disabled arm with
/// `--dart-define=FLAME_3D_WEBGPU_BIND_CACHE=false`.
const bool webGpuBindCacheEnabled = bool.fromEnvironment(
  'FLAME_3D_WEBGPU_BIND_CACHE',
  defaultValue: true,
);

/// This slice intentionally targets only the stable material/camera group.
const int webGpuBindCacheTargetGroup = 1;

const int _defaultCounterLimit = 0x7FFFFFFF;

/// One pooled uniform-buffer suballocation.
@internal
@immutable
final class WebGpuUniformAllocation {
  const WebGpuUniformAllocation({
    required this.bufferToken,
    required this.offset,
    required this.size,
    required this.revision,
  });

  final Object bufferToken;
  final int offset;
  final int size;
  final int revision;
}

/// One ordered resource in a bind-group key.
@internal
sealed class WebGpuBindResourceKey {
  const WebGpuBindResourceKey();
}

/// A uniform buffer binding in a complete bind-group key.
@internal
@immutable
final class WebGpuUniformBindKey extends WebGpuBindResourceKey {
  const WebGpuUniformBindKey({
    required this.binding,
    required this.bufferToken,
    required this.offset,
    required this.size,
    required this.revision,
  });

  final int binding;
  final Object bufferToken;
  final int offset;
  final int size;
  final int revision;

  @override
  bool operator ==(Object other) {
    return other is WebGpuUniformBindKey &&
        binding == other.binding &&
        identical(bufferToken, other.bufferToken) &&
        offset == other.offset &&
        size == other.size &&
        revision == other.revision;
  }

  @override
  int get hashCode => Object.hash(
    binding,
    identityHashCode(bufferToken),
    offset,
    size,
    revision,
  );
}

/// A sampled texture and its sampler in a complete bind-group key.
@internal
@immutable
final class WebGpuTextureBindKey extends WebGpuBindResourceKey {
  const WebGpuTextureBindKey({
    required this.binding,
    required this.samplerBinding,
    required this.viewToken,
    required this.samplerToken,
  });

  final int binding;
  final int samplerBinding;
  final Object viewToken;
  final Object samplerToken;

  @override
  bool operator ==(Object other) {
    return other is WebGpuTextureBindKey &&
        binding == other.binding &&
        samplerBinding == other.samplerBinding &&
        identical(viewToken, other.viewToken) &&
        identical(samplerToken, other.samplerToken);
  }

  @override
  int get hashCode => Object.hash(
    binding,
    samplerBinding,
    identityHashCode(viewToken),
    identityHashCode(samplerToken),
  );
}

/// Exactly one retained view slot owned by a sampled-texture resource.
@internal
final class WebGpuTextureViewLifetime<T extends Object> {
  T? _view;

  /// Resolves a retained fallback view without frame-local accounting.
  T resolveUntracked(T Function() create) {
    return _view ??= create();
  }

  T _resolve({
    required T Function() create,
    required void Function() onHit,
    required void Function() onMiss,
  }) {
    final cached = _view;
    if (cached != null) {
      onHit();
      return cached;
    }

    onMiss();
    return _view = create();
  }
}

/// Platform-neutral policy for the WebGPU group-1 cache.
///
/// GPU objects are opaque identity tokens. The Web backend supplies the real
/// allocation and creation callbacks; VM and browser tests supply fake tokens.
@internal
final class WebGpuBindCachePolicy {
  WebGpuBindCachePolicy()
    : enabled = webGpuBindCacheEnabled,
      _counterLimit = _defaultCounterLimit {
    _initializeCounters();
  }

  /// Allows both production branches to execute in one fake-device test run.
  @visibleForTesting
  WebGpuBindCachePolicy.forTesting({
    required this.enabled,
    int counterLimit = _defaultCounterLimit,
  }) : assert(counterLimit > 0),
       _counterLimit = counterLimit {
    _initializeCounters();
  }

  final bool enabled;
  final int _counterLimit;

  final Map<_UniformUploadKey, WebGpuUniformAllocation> _uniformUploads = {};
  final Map<_BindGroupKey, Object> _bindGroups = {};
  final _CounterState _currentCounters = _CounterState();
  final _CounterState _lastCounters = _CounterState();

  bool _frameActive = false;

  GpuBindCacheCounters get lastCounters => _lastCounters;

  void _initializeCounters() {
    _currentCounters.reset(enabled: enabled);
    _lastCounters.reset(enabled: enabled);
  }

  /// Starts a frame with empty upload and bind-group caches.
  void beginFrame() {
    _uniformUploads.clear();
    _bindGroups.clear();
    _currentCounters.reset(enabled: enabled);
    _frameActive = true;
  }

  /// Publishes counters and drops every reference to frame-local GPU objects.
  void endFrame() {
    _ensureFrameActive();
    _lastCounters.copyFrom(_currentCounters);
    _uniformUploads.clear();
    _bindGroups.clear();
    _frameActive = false;
  }

  /// Resolves the sampled texture's retained view for the target group.
  ///
  /// Disabled or non-target groups call [create] exactly as the upstream path.
  T resolveTextureView<T extends Object>({
    required int group,
    required WebGpuTextureViewLifetime<T> lifetime,
    required T Function() create,
  }) {
    _ensureFrameActive();
    if (group != webGpuBindCacheTargetGroup) {
      return create();
    }
    if (!enabled) {
      _currentCounters.incrementTextureViewMiss(_counterLimit);
      return create();
    }

    return lifetime._resolve(
      create: create,
      onHit: () => _currentCounters.incrementTextureViewHit(_counterLimit),
      onMiss: () => _currentCounters.incrementTextureViewMiss(_counterLimit),
    );
  }

  /// Reuses one upload for a stable binding identity/revision within a frame.
  WebGpuUniformAllocation resolveUniformUpload({
    required int group,
    required int binding,
    required Object? bindingIdentity,
    required int revision,
    required int size,
    required WebGpuUniformAllocation Function() upload,
  }) {
    _ensureFrameActive();
    if (group != webGpuBindCacheTargetGroup) {
      return upload();
    }
    if (!enabled || bindingIdentity == null) {
      _currentCounters.incrementUniformUploadMiss(_counterLimit);
      return upload();
    }

    final key = _UniformUploadKey(
      group: group,
      binding: binding,
      bindingIdentity: bindingIdentity,
      revision: revision,
      size: size,
    );
    final cached = _uniformUploads[key];
    if (cached != null) {
      _currentCounters.incrementUniformUploadHit(_counterLimit);
      return cached;
    }

    _currentCounters.incrementUniformUploadMiss(_counterLimit);
    final allocation = upload();
    assert(allocation.size == size);
    assert(allocation.revision == revision);
    _uniformUploads[key] = allocation;
    return allocation;
  }

  /// Reuses a bind group only when its complete ordered resource key matches.
  T resolveBindGroup<T extends Object>({
    required Object pipelineToken,
    required Object layoutToken,
    required int group,
    required List<WebGpuBindResourceKey> resources,
    required T Function() create,
  }) {
    _ensureFrameActive();
    if (group != webGpuBindCacheTargetGroup) {
      return create();
    }
    if (!enabled) {
      _currentCounters.incrementBindGroupMiss(_counterLimit);
      return create();
    }

    final key = _BindGroupKey(
      pipelineToken: pipelineToken,
      layoutToken: layoutToken,
      group: group,
      resources: resources,
    );
    final cached = _bindGroups[key];
    if (cached != null) {
      _currentCounters.incrementBindGroupHit(_counterLimit);
      return cached as T;
    }

    _currentCounters.incrementBindGroupMiss(_counterLimit);
    final bindGroup = create();
    _bindGroups[key] = bindGroup;
    return bindGroup;
  }

  void _ensureFrameActive() {
    if (!_frameActive) {
      throw StateError('WebGPU bind-cache operation outside an active frame.');
    }
  }
}

@immutable
final class _UniformUploadKey {
  const _UniformUploadKey({
    required this.group,
    required this.binding,
    required this.bindingIdentity,
    required this.revision,
    required this.size,
  });

  final int group;
  final int binding;
  final Object bindingIdentity;
  final int revision;
  final int size;

  @override
  bool operator ==(Object other) {
    return other is _UniformUploadKey &&
        group == other.group &&
        binding == other.binding &&
        identical(bindingIdentity, other.bindingIdentity) &&
        revision == other.revision &&
        size == other.size;
  }

  @override
  int get hashCode => Object.hash(
    group,
    binding,
    identityHashCode(bindingIdentity),
    revision,
    size,
  );
}

@immutable
final class _BindGroupKey {
  _BindGroupKey({
    required this.pipelineToken,
    required this.layoutToken,
    required this.group,
    required List<WebGpuBindResourceKey> resources,
  }) : resources = List.unmodifiable(resources);

  final Object pipelineToken;
  final Object layoutToken;
  final int group;
  final List<WebGpuBindResourceKey> resources;

  @override
  bool operator ==(Object other) {
    if (other is! _BindGroupKey ||
        !identical(pipelineToken, other.pipelineToken) ||
        !identical(layoutToken, other.layoutToken) ||
        group != other.group ||
        resources.length != other.resources.length) {
      return false;
    }
    for (var i = 0; i < resources.length; i++) {
      if (resources[i] != other.resources[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    identityHashCode(pipelineToken),
    identityHashCode(layoutToken),
    group,
    Object.hashAll(resources),
  );
}

final class _CounterState implements GpuBindCacheCounters {
  bool _enabled = false;

  @override
  bool get enabled => _enabled;

  @override
  int get targetGroup => webGpuBindCacheTargetGroup;

  @override
  int textureViewHits = 0;

  @override
  int textureViewMisses = 0;

  @override
  int uniformUploadHits = 0;

  @override
  int uniformUploadMisses = 0;

  @override
  int bindGroupHits = 0;

  @override
  int bindGroupMisses = 0;

  void reset({required bool enabled}) {
    _enabled = enabled;
    textureViewHits = 0;
    textureViewMisses = 0;
    uniformUploadHits = 0;
    uniformUploadMisses = 0;
    bindGroupHits = 0;
    bindGroupMisses = 0;
  }

  void copyFrom(_CounterState other) {
    _enabled = other._enabled;
    textureViewHits = other.textureViewHits;
    textureViewMisses = other.textureViewMisses;
    uniformUploadHits = other.uniformUploadHits;
    uniformUploadMisses = other.uniformUploadMisses;
    bindGroupHits = other.bindGroupHits;
    bindGroupMisses = other.bindGroupMisses;
  }

  void incrementTextureViewHit(int limit) {
    textureViewHits = _increment(textureViewHits, limit);
  }

  void incrementTextureViewMiss(int limit) {
    textureViewMisses = _increment(textureViewMisses, limit);
  }

  void incrementUniformUploadHit(int limit) {
    uniformUploadHits = _increment(uniformUploadHits, limit);
  }

  void incrementUniformUploadMiss(int limit) {
    uniformUploadMisses = _increment(uniformUploadMisses, limit);
  }

  void incrementBindGroupHit(int limit) {
    bindGroupHits = _increment(bindGroupHits, limit);
  }

  void incrementBindGroupMiss(int limit) {
    bindGroupMisses = _increment(bindGroupMisses, limit);
  }

  static int _increment(int value, int limit) {
    return value < limit ? value + 1 : limit;
  }
}
