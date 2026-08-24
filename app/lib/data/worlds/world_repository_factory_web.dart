import 'web_world_repository.dart';
import 'world_repository.dart';

Future<WorldRepository> createDefaultWorldRepository() async =>
    WebWorldRepository();
