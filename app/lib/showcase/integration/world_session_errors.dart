/// Typed outcomes returned by public world-session commands.
sealed class WorldSessionResult<T> {
  const WorldSessionResult();
}

final class WorldSessionSuccess<T> extends WorldSessionResult<T> {
  const WorldSessionSuccess(this.value);
  final T value;
}

final class WorldSessionCancelled<T> extends WorldSessionResult<T> {
  const WorldSessionCancelled();
}

final class WorldSessionFailure<T> extends WorldSessionResult<T> {
  const WorldSessionFailure(
    this.error, {
    this.activeWorldChanged = false,
    this.durableStateChanged = false,
    this.cleanupErrors = const [],
  });

  final Object error;
  final bool activeWorldChanged;
  final bool durableStateChanged;
  final List<Object> cleanupErrors;

  @override
  String toString() =>
      '$error${cleanupErrors.isEmpty ? '' : '; cleanup: ${cleanupErrors.join('; ')}'}';
}

/// Internal transaction exception. Public commands convert it to a result.
final class WorldSessionException implements Exception {
  const WorldSessionException(
    this.error, {
    this.durableStateChanged = false,
    this.cleanupErrors = const [],
  });

  final Object error;
  final bool durableStateChanged;
  final List<Object> cleanupErrors;

  static WorldSessionException fromFailure<T>(
    WorldSessionFailure<T> failure, {
    Iterable<Object> additionalCleanup = const [],
  }) => WorldSessionException(
    failure.error,
    durableStateChanged: failure.durableStateChanged,
    cleanupErrors: [...failure.cleanupErrors, ...additionalCleanup],
  );

  WorldSessionFailure<T> toFailure<T>({bool activeWorldChanged = false}) =>
      WorldSessionFailure<T>(
        error,
        activeWorldChanged: activeWorldChanged,
        durableStateChanged: durableStateChanged,
        cleanupErrors: cleanupErrors,
      );

  @override
  String toString() =>
      '$error${cleanupErrors.isEmpty ? '' : '; cleanup: ${cleanupErrors.join('; ')}'}';
}
