/// Platform facade for importing the previous single-file MDRT1 save.
library;

export 'legacy_world_migration_stub.dart'
    if (dart.library.io) 'legacy_world_migration_io.dart';
