/// Platform-selected production repository factory.
library;

import 'world_repository.dart';
import 'world_repository_factory_stub.dart'
    if (dart.library.io) 'world_repository_factory_io.dart'
    if (dart.library.js_interop) 'world_repository_factory_web.dart'
    as implementation;

Future<WorldRepository> createDefaultWorldRepository() =>
    implementation.createDefaultWorldRepository();
