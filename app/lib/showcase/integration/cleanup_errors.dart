import 'world_session_errors.dart';

/// Collects cleanup failures while preserving their original order.
final class CleanupErrors {
  final List<Object> _values = <Object>[];

  bool get isEmpty => _values.isEmpty;
  Object get first => _values.first;
  List<Object> get rest => List<Object>.unmodifiable(_values.skip(1));
  List<Object> get values => List<Object>.unmodifiable(_values);

  void add(Object error) {
    if (error is WorldSessionException) {
      _values
        ..add(error.error)
        ..addAll(error.cleanupErrors);
    } else {
      _values.add(error);
    }
  }

  void addCleanup(Object error) {
    if (error case WorldSessionException(:final cleanupErrors)) {
      _values.addAll(cleanupErrors);
    } else {
      _values.add(error);
    }
  }

  void addAll(Iterable<Object> errors) {
    for (final error in errors) {
      _values.add(error);
    }
  }
}

/// Runs [operation], then cleanup, retaining both failures if cleanup fails.
Future<void> runWithCleanup(
  Future<void> Function() operation,
  Future<void> Function() cleanup,
) async {
  try {
    await operation();
  } catch (error) {
    try {
      await cleanup();
    } catch (cleanupError) {
      final failures = CleanupErrors();
      if (error is WorldSessionException) {
        failures.addAll(error.cleanupErrors);
      }
      failures.add(cleanupError);
      final primary = error is WorldSessionException ? error.error : error;
      throw WorldSessionException(primary, cleanupErrors: failures.values);
    }
    rethrow;
  }
  await cleanup();
}
