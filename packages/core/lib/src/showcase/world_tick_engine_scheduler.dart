part of 'world_tick_engine.dart';

extension on WorldTickEngine {
  void _scheduleWorldCell(
    VoxelWorld world,
    int x,
    int y,
    int z, {
    int? previousRaw,
  }) {
    if (!VoxelWorld.inBounds(x, y, z)) return;
    final raw = world.blockAt(x, y, z);
    final behavior = WorldTickEngine._behaviorForRaw(raw);
    _reconcileSpongeState(world, x, y, z, behavior, previousRaw: previousRaw);
    if (behavior == BlockBehavior.water || behavior == BlockBehavior.lava) {
      final id = Blocks.id(raw);
      _scheduleLiquid(
        x,
        y,
        z,
        id,
        _currentTick + WorldTickEngine._fluidDelay(id),
      );
      return;
    }
    if (behavior == BlockBehavior.sponge) {
      if (_hasWaterNearby(world, x, y, z)) _scheduleGeneric(x, y, z);
      return;
    }
    if (behavior == BlockBehavior.falling) {
      _scheduleGeneric(x, y, z);
      return;
    }
    if (behavior == BlockBehavior.tnt &&
        _tntFuses.containsKey(worldPositionKey(x, y, z))) {
      _scheduleGeneric(x, y, z);
    }
  }

  bool _scheduleGeneric(int x, int y, int z) => _scheduleKey(
    worldPositionKey(x, y, z),
    expectedLiquidId: _genericIdentity,
    dueTick: _currentTick + 1,
  );

  bool _scheduleLiquid(int x, int y, int z, int liquidId, int dueTick) =>
      _scheduleKey(
        worldPositionKey(x, y, z),
        expectedLiquidId: liquidId,
        dueTick: dueTick,
      );

  bool _scheduleKey(
    int key, {
    required int expectedLiquidId,
    required int dueTick,
    bool markRetry = true,
  }) {
    final identity = WorldTickEngine._scheduleIdentity(key, expectedLiquidId);
    if (_scheduled.containsKey(identity)) return false;
    if (_scheduled.length >= maxQueue) {
      _droppedUpdates++;
      if (markRetry) _markRetryAroundKey(key);
      return false;
    }
    final normalizedDue = dueTick <= _currentTick ? _currentTick + 1 : dueTick;
    final entry = _ScheduledEntry(
      key: key,
      expectedLiquidId: expectedLiquidId,
      dueTick: normalizedDue,
      sequence: _nextSequence++,
    );
    _scheduled[identity] = entry;
    _heapPush(entry);
    return true;
  }

  bool _hasGenericScheduled(int key) => _scheduled.containsKey(
    WorldTickEngine._scheduleIdentity(key, _genericIdentity),
  );

  void _promoteRetries(VoxelWorld world) {
    if (_retryChunkCount == 0 || _scheduled.length >= maxQueue) return;
    var scannedChunks = 0;
    for (
      var chunkIndex = 0;
      chunkIndex < _worldChunkCount && scannedChunks < _retryChunksPerTick;
      chunkIndex++
    ) {
      if (!_isRetryMarked(chunkIndex)) continue;
      scannedChunks++;
      // Clear before scanning so overflow caused by reconciliation can re-mark
      // this same chunk without being erased at the end of the pass.
      _clearRetryChunk(chunkIndex);
      final chunk = world.chunks[chunkIndex];
      for (var localIndex = 0; localIndex < ChunkIndex.volume; localIndex++) {
        if (_scheduled.length >= maxQueue) {
          _markRetryChunk(chunkIndex);
          return;
        }
        final raw = chunk.blocks[localIndex];
        final behavior = WorldTickEngine._behaviorForRaw(raw);
        final (x, y, z) = WorldTickEngine._worldCoordinates(chunk, localIndex);
        _reconcileSpongeState(world, x, y, z, behavior);
        if (behavior == BlockBehavior.water || behavior == BlockBehavior.lava) {
          if (_needsFluidUpdate(world, x, y, z, raw)) {
            _scheduleKey(
              worldPositionKey(x, y, z),
              expectedLiquidId: Blocks.id(raw),
              dueTick:
                  _currentTick + WorldTickEngine._fluidDelay(Blocks.id(raw)),
              markRetry: false,
            );
          }
        } else if (behavior == BlockBehavior.falling) {
          if (y > 0 && Blocks.id(world.blockAt(x, y - 1, z)) == Blocks.air) {
            _scheduleKey(
              worldPositionKey(x, y, z),
              expectedLiquidId: _genericIdentity,
              dueTick: _currentTick + 1,
              markRetry: false,
            );
          }
        } else if (behavior == BlockBehavior.sponge) {
          if (_hasWaterNearby(world, x, y, z)) {
            _scheduleKey(
              worldPositionKey(x, y, z),
              expectedLiquidId: _genericIdentity,
              dueTick: _currentTick + 1,
              markRetry: false,
            );
          }
        } else if (behavior == BlockBehavior.tnt &&
            _tntFuses.containsKey(worldPositionKey(x, y, z))) {
          _scheduleKey(
            worldPositionKey(x, y, z),
            expectedLiquidId: _genericIdentity,
            dueTick: _currentTick + 1,
            markRetry: false,
          );
        }
        if (_scheduled.length >= maxQueue &&
            localIndex + 1 < ChunkIndex.volume) {
          _markRetryChunk(chunkIndex);
          return;
        }
      }
    }
  }

  void _markRetryAroundKey(int key) {
    final (x, y, z) = WorldTickEngine._decodePosition(key);
    final cx = x >> 4;
    final cy = y >> 4;
    final cz = z >> 4;
    final lx = x & 15;
    final ly = y & 15;
    final lz = z & 15;
    final minCx = lx == 0 && cx > 0 ? cx - 1 : cx;
    final maxCx = lx == 15 && cx < WorldDims.worldChunksX - 1 ? cx + 1 : cx;
    final minCy = ly == 0 && cy > 0 ? cy - 1 : cy;
    final maxCy = ly == 15 && cy < WorldDims.worldChunksY - 1 ? cy + 1 : cy;
    final minCz = lz == 0 && cz > 0 ? cz - 1 : cz;
    final maxCz = lz == 15 && cz < WorldDims.worldChunksZ - 1 ? cz + 1 : cz;
    for (var retryCy = minCy; retryCy <= maxCy; retryCy++) {
      for (var retryCz = minCz; retryCz <= maxCz; retryCz++) {
        for (var retryCx = minCx; retryCx <= maxCx; retryCx++) {
          _markRetryChunk(VoxelWorld.chunkIndexOf(retryCx, retryCy, retryCz));
        }
      }
    }
  }

  void _markRetryChunk(int chunkIndex) {
    final word = chunkIndex ~/ _bitsPerRetryWord;
    final mask = 1 << (chunkIndex % _bitsPerRetryWord);
    if ((_retryWords[word] & mask) != 0) return;
    _retryWords[word] |= mask;
    _retryChunkCount++;
  }

  bool _isRetryMarked(int chunkIndex) {
    final word = chunkIndex ~/ _bitsPerRetryWord;
    final mask = 1 << (chunkIndex % _bitsPerRetryWord);
    return (_retryWords[word] & mask) != 0;
  }

  void _clearRetryChunk(int chunkIndex) {
    final word = chunkIndex ~/ _bitsPerRetryWord;
    final mask = 1 << (chunkIndex % _bitsPerRetryWord);
    if ((_retryWords[word] & mask) == 0) return;
    _retryWords[word] &= ~mask;
    _retryChunkCount--;
  }

  void _heapPush(_ScheduledEntry entry) {
    var index = _heap.length;
    _heap.add(entry);
    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (!WorldTickEngine._entryBefore(entry, _heap[parent])) break;
      _heap[index] = _heap[parent];
      index = parent;
    }
    _heap[index] = entry;
  }

  _ScheduledEntry? _peekScheduled() => _heap.isEmpty ? null : _heap.first;

  _ScheduledEntry? _popScheduled() {
    if (_heap.isEmpty) return null;
    final first = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isEmpty) return first;
    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      if (left >= _heap.length) break;
      final right = left + 1;
      var child = left;
      if (right < _heap.length &&
          WorldTickEngine._entryBefore(_heap[right], _heap[left])) {
        child = right;
      }
      if (!WorldTickEngine._entryBefore(_heap[child], last)) break;
      _heap[index] = _heap[child];
      index = child;
    }
    _heap[index] = last;
    return first;
  }
}
