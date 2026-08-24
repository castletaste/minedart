import 'native_world_repository.dart';
import 'world_repository.dart';

Future<WorldRepository> createDefaultWorldRepository() =>
    NativeWorldRepository.createDefault();
