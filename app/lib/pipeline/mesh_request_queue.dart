/// Deterministic, synchronous scheduling for chunk mesh requests.
///
/// This module deliberately stores only chunk coordinates and generations.
/// Snapshot capture and meshing stay with the platform pipeline so requests can
/// be coalesced before either expensive operation begins.
library;

/// Result of reporting a failed mesh attempt to [MeshRequestQueue].
enum MeshFailureOutcome {
  /// The request was still current and another attempt was queued.
  retryScheduled,

  /// The request was still current, but its retry allowance was exhausted.
  retryLimitReached,

  /// A newer generation or attempt already superseded this request.
  stale,

  /// The queue has been disposed and ignored the result.
  disposed,
}

/// A chunk mesh request captured from [MeshRequestQueue] for processing.
///
/// [retryCount] is zero for the first attempt. The request is an immutable
/// token: pass the same instance to [MeshRequestQueue.complete] or
/// [MeshRequestQueue.fail] when processing finishes.
final class MeshRequest {
  const MeshRequest._({
    required this.chunkIndex,
    required this.chunkX,
    required this.chunkY,
    required this.chunkZ,
    required this.generation,
    required this.retryCount,
    required this.distanceSquared,
    required int ticket,
  }) : // Keep the private token out of the public named-argument spelling.
       // ignore: prefer_initializing_formals
       _ticket = ticket;

  final int chunkIndex;
  final int chunkX;
  final int chunkY;
  final int chunkZ;
  final int generation;
  final int retryCount;

  /// Squared chunk distance from the priority origin when this attempt was
  /// taken. It is diagnostic only; queued requests are reprioritized when the
  /// origin changes.
  final int distanceSquared;

  final int _ticket;
}

/// Newest-generation-per-chunk queue backed by a deterministic min-heap.
///
/// Normal requests are ordered by nearest squared chunk distance, then chunk
/// index and generation. Retries form later scheduling tiers, which lets every
/// less-retried request make progress before a repeatedly failing request is
/// attempted again.
///
/// Replaced heap nodes are removed lazily. Automatic compaction bounds their
/// retained count to `pendingCount * compactionFactor + compactionSlack`.
final class MeshRequestQueue {
  MeshRequestQueue({
    int originChunkX = 0,
    int originChunkY = 0,
    int originChunkZ = 0,
    this.maxRetries = 2,
    int compactionFactor = 2,
    int compactionSlack = 32,
  }) : // Public constructor arguments intentionally omit private underscores.
       // ignore: prefer_initializing_formals
       _originChunkX = originChunkX,
       // ignore: prefer_initializing_formals
       _originChunkY = originChunkY,
       // ignore: prefer_initializing_formals
       _originChunkZ = originChunkZ,
       _compactionFactor = compactionFactor,
       _compactionSlack = compactionSlack {
    if (maxRetries < 0) {
      throw ArgumentError.value(
        maxRetries,
        'maxRetries',
        'must be non-negative',
      );
    }
    if (compactionFactor < 1) {
      throw ArgumentError.value(
        compactionFactor,
        'compactionFactor',
        'must be at least one',
      );
    }
    if (compactionSlack < 0) {
      throw ArgumentError.value(
        compactionSlack,
        'compactionSlack',
        'must be non-negative',
      );
    }
  }

  /// Number of retries after the initial attempt.
  final int maxRetries;

  final int _compactionFactor;
  final int _compactionSlack;
  final Map<int, int> _latestGenerations = <int, int>{};
  final Map<int, _QueueEntry> _entries = <int, _QueueEntry>{};
  final List<_HeapNode> _heap = <_HeapNode>[];

  int _originChunkX;
  int _originChunkY;
  int _originChunkZ;
  int _nextTicket = 0;
  int _queuedCount = 0;
  int _compactionCount = 0;
  int _originRebuildCount = 0;
  int _staleDiscardCount = 0;
  bool _disposed = false;

  int get pendingCount => _queuedCount;
  int get activeCount => _entries.length;
  bool get isEmpty => _queuedCount == 0;
  bool get isDisposed => _disposed;

  ({int x, int y, int z}) get priorityOrigin =>
      (x: _originChunkX, y: _originChunkY, z: _originChunkZ);

  /// Heap diagnostics are useful for queue telemetry and deterministic tests.
  int get heapNodeCount => _heap.length;
  int get staleNodeCount => _heap.length - _queuedCount;
  int get compactionCount => _compactionCount;
  int get originRebuildCount => _originRebuildCount;
  int get staleDiscardCount => _staleDiscardCount;

  /// Adds a generation without capturing a chunk snapshot.
  ///
  /// Returns false when this generation is not newer than the chunk's known
  /// generation, or when the queue has been disposed.
  bool request({
    required int chunkIndex,
    required int chunkX,
    required int chunkY,
    required int chunkZ,
    required int generation,
  }) {
    if (_disposed) return false;

    final latestGeneration = _latestGenerations[chunkIndex];
    if (latestGeneration != null && generation <= latestGeneration) {
      return false;
    }

    _latestGenerations[chunkIndex] = generation;
    final previous = _entries[chunkIndex];
    if (previous == null || !previous.queued) {
      _queuedCount++;
    }

    final entry = _QueueEntry(
      chunkIndex: chunkIndex,
      chunkX: chunkX,
      chunkY: chunkY,
      chunkZ: chunkZ,
      generation: generation,
      ticket: _nextTicket++,
    );
    _entries[chunkIndex] = entry;
    _pushEntry(entry);
    _maybeCompact();
    return true;
  }

  /// Removes and returns the highest-priority current request, if any.
  MeshRequest? takeNext() {
    if (_disposed) return null;

    while (_heap.isNotEmpty) {
      final node = _removeMin();
      final entry = _entries[node.chunkIndex];
      if (entry == null || !entry.matches(node)) {
        _staleDiscardCount++;
        continue;
      }

      entry
        ..queued = false
        ..inFlight = true;
      _queuedCount--;
      final request = MeshRequest._(
        chunkIndex: entry.chunkIndex,
        chunkX: entry.chunkX,
        chunkY: entry.chunkY,
        chunkZ: entry.chunkZ,
        generation: entry.generation,
        retryCount: entry.retryCount,
        distanceSquared: node.distanceSquared,
        ticket: entry.ticket,
      );
      _maybeCompact();
      return request;
    }

    assert(_queuedCount == 0, 'A queued request must have a live heap node.');
    return null;
  }

  /// Completes [request] if it is the current in-flight attempt.
  ///
  /// A false result means the attempt was disposed or superseded. Its result
  /// must not be published.
  bool complete(MeshRequest request) {
    if (_disposed) return false;
    final entry = _currentInFlightEntry(request);
    if (entry == null) return false;

    entry.inFlight = false;
    _entries.remove(request.chunkIndex);
    _maybeCompact();
    return true;
  }

  /// Reports a failed attempt and schedules a bounded retry when still current.
  MeshFailureOutcome fail(MeshRequest request) {
    if (_disposed) return MeshFailureOutcome.disposed;
    final entry = _currentInFlightEntry(request);
    if (entry == null) return MeshFailureOutcome.stale;

    entry.inFlight = false;
    if (entry.retryCount >= maxRetries) {
      _entries.remove(request.chunkIndex);
      _maybeCompact();
      return MeshFailureOutcome.retryLimitReached;
    }

    entry
      ..retryCount += 1
      ..nodeVersion += 1
      ..queued = true;
    _queuedCount++;
    _pushEntry(entry);
    _maybeCompact();
    return MeshFailureOutcome.retryScheduled;
  }

  /// Whether [generation] is the newest generation ever accepted for a chunk.
  ///
  /// Completed and retry-exhausted generations remain as watermarks so a late
  /// stale request cannot resurrect old work.
  bool isLatestGeneration(int chunkIndex, int generation) =>
      !_disposed && _latestGenerations[chunkIndex] == generation;

  /// Whether [request] is the current in-flight attempt.
  bool isCurrent(MeshRequest request) =>
      !_disposed && _currentInFlightEntry(request) != null;

  /// Rebuilds all queued priorities when the origin moves to another chunk.
  bool setPriorityOrigin({required int x, required int y, required int z}) {
    if (_disposed) return false;
    if (_originChunkX == x && _originChunkY == y && _originChunkZ == z) {
      return false;
    }

    _originChunkX = x;
    _originChunkY = y;
    _originChunkZ = z;
    _originRebuildCount++;
    _rebuildHeap();
    return true;
  }

  /// Removes all stale nodes immediately. Returns false after disposal.
  bool compact() {
    if (_disposed) return false;
    _compactionCount++;
    _rebuildHeap();
    return true;
  }

  /// Drops all queued/in-flight state and generation watermarks.
  ///
  /// Disposal is synchronous and idempotent. Later requests and results are
  /// ignored.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _queuedCount = 0;
    _heap.clear();
    _entries.clear();
    _latestGenerations.clear();
  }

  _QueueEntry? _currentInFlightEntry(MeshRequest request) {
    final entry = _entries[request.chunkIndex];
    if (entry == null ||
        !entry.inFlight ||
        entry.ticket != request._ticket ||
        entry.generation != request.generation ||
        entry.retryCount != request.retryCount) {
      return null;
    }
    return entry;
  }

  void _pushEntry(_QueueEntry entry) {
    final dx = entry.chunkX - _originChunkX;
    final dy = entry.chunkY - _originChunkY;
    final dz = entry.chunkZ - _originChunkZ;
    _addNode(
      _HeapNode(
        chunkIndex: entry.chunkIndex,
        generation: entry.generation,
        retryCount: entry.retryCount,
        ticket: entry.ticket,
        nodeVersion: entry.nodeVersion,
        distanceSquared: dx * dx + dy * dy + dz * dz,
      ),
    );
  }

  void _maybeCompact() {
    if (_queuedCount == 0) {
      if (_heap.isNotEmpty) {
        _compactionCount++;
        _heap.clear();
      }
      return;
    }

    final maximumNodes = _queuedCount * _compactionFactor + _compactionSlack;
    if (_heap.length > maximumNodes) {
      _compactionCount++;
      _rebuildHeap();
    }
  }

  void _rebuildHeap() {
    _heap.clear();
    for (final entry in _entries.values) {
      if (entry.queued) _pushEntry(entry);
    }
  }

  void _addNode(_HeapNode node) {
    _heap.add(node);
    var index = _heap.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_compareNodes(_heap[parent], node) <= 0) break;
      _heap[index] = _heap[parent];
      index = parent;
    }
    _heap[index] = node;
  }

  _HeapNode _removeMin() {
    final result = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isEmpty) return result;

    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      if (left >= _heap.length) break;
      final right = left + 1;
      var child = left;
      if (right < _heap.length &&
          _compareNodes(_heap[right], _heap[left]) < 0) {
        child = right;
      }
      if (_compareNodes(last, _heap[child]) <= 0) break;
      _heap[index] = _heap[child];
      index = child;
    }
    _heap[index] = last;
    return result;
  }
}

final class _QueueEntry {
  _QueueEntry({
    required this.chunkIndex,
    required this.chunkX,
    required this.chunkY,
    required this.chunkZ,
    required this.generation,
    required this.ticket,
  });

  final int chunkIndex;
  final int chunkX;
  final int chunkY;
  final int chunkZ;
  final int generation;
  final int ticket;
  int retryCount = 0;
  int nodeVersion = 0;
  bool queued = true;
  bool inFlight = false;

  bool matches(_HeapNode node) =>
      queued &&
      ticket == node.ticket &&
      generation == node.generation &&
      retryCount == node.retryCount &&
      nodeVersion == node.nodeVersion;
}

final class _HeapNode {
  const _HeapNode({
    required this.chunkIndex,
    required this.generation,
    required this.retryCount,
    required this.ticket,
    required this.nodeVersion,
    required this.distanceSquared,
  });

  final int chunkIndex;
  final int generation;
  final int retryCount;
  final int ticket;
  final int nodeVersion;
  final int distanceSquared;
}

int _compareNodes(_HeapNode a, _HeapNode b) {
  var order = a.retryCount.compareTo(b.retryCount);
  if (order != 0) return order;
  order = a.distanceSquared.compareTo(b.distanceSquared);
  if (order != 0) return order;
  order = a.chunkIndex.compareTo(b.chunkIndex);
  if (order != 0) return order;
  order = a.generation.compareTo(b.generation);
  if (order != 0) return order;
  order = a.ticket.compareTo(b.ticket);
  if (order != 0) return order;
  return a.nodeVersion.compareTo(b.nodeVersion);
}
