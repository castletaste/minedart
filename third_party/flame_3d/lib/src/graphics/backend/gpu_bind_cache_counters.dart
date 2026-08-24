/// Read-only counters for the most recently completed GPU frame's bind cache.
///
/// Backends that do not implement a bind cache expose no counters. The WebGPU
/// backend currently targets exactly one bind group, reported by [targetGroup].
abstract interface class GpuBindCacheCounters {
  /// Whether the cache was enabled for the completed frame.
  bool get enabled;

  /// The only bind group included in these counters.
  int get targetGroup;

  /// Sampled-texture view lookups served by a retained view.
  int get textureViewHits;

  /// Sampled-texture view lookups that called `createView()`.
  int get textureViewMisses;

  /// Uniform uploads reused within the frame.
  int get uniformUploadHits;

  /// Uniform uploads issued to the GPU queue within the frame.
  int get uniformUploadMisses;

  /// Bind groups reused within the frame.
  int get bindGroupHits;

  /// Bind groups created within the frame.
  int get bindGroupMisses;
}
