import 'world_repository.dart';

Future<WorldRepository> createDefaultWorldRepository() =>
    Future<WorldRepository>.error(
      UnsupportedError('World persistence is unavailable on this platform'),
    );
