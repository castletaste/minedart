import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/controller/world_library_controller.dart';
import 'package:minedart/showcase/ui/world_library.dart';

void main() {
  testWidgets('world cards route actions and confirm destructive callbacks', (
    tester,
  ) async {
    _setViewport(tester, width: 800);
    final world = WorldLibraryEntry(
      id: 'alpha',
      name: 'Alpha Valley',
      seed: 4242,
      updatedAt: DateTime.utc(2026, 8, 24, 10, 30),
      isCurrent: true,
    );
    final controller = WorldLibraryController(
      worlds: <WorldLibraryEntry>[world],
    );
    addTearDown(controller.dispose);
    String? loaded;
    String? renamed;
    var duplicates = 0;
    var deletes = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: WorldLibraryView(
            controller: controller,
            callbacks: WorldLibraryCallbacks(
              onCreate: (name, seed, preset) async {},
              onImport: () async {},
              onLoad: (entry) async => loaded = entry.id,
              onRename: (entry, name) async => renamed = name,
              onDuplicate: (entry) async => duplicates++,
              onDelete: (entry) async => deletes++,
              onReset: (entry) async {},
              onExport: (entry) async {},
              onShareSeed: (entry) async {},
            ),
            onClose: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(WorldLibraryKeys.load(world.id)));
    await tester.pumpAndSettle();
    expect(loaded, world.id);

    await _chooseAction(tester, world.id, WorldLibraryAction.duplicate.label);
    expect(duplicates, 1);

    await _chooseAction(tester, world.id, WorldLibraryAction.rename.label);
    final renameField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(renameField, 'Quartz Ridge');
    await tester.tap(find.byKey(WorldLibraryKeys.confirmRename));
    await tester.pumpAndSettle();
    expect(renamed, 'Quartz Ridge');

    await _chooseAction(tester, world.id, WorldLibraryAction.delete.label);
    expect(find.text('Delete Alpha Valley?'), findsOneWidget);
    expect(deletes, 0);
    await tester.tap(find.byKey(WorldLibraryKeys.confirmDestructive));
    await tester.pumpAndSettle();
    expect(deletes, 1);
  });

  testWidgets('create/import callbacks and card semantics stay UI-only', (
    tester,
  ) async {
    _setViewport(tester, width: 480);
    final world = WorldLibraryEntry(
      id: 'beta',
      name: 'Beta Shore',
      seed: 99,
      updatedAt: DateTime.utc(2026, 8, 24),
    );
    final controller = WorldLibraryController(
      worlds: <WorldLibraryEntry>[world],
    );
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    ({String name, int? seed, WorldLibraryPreset preset})? created;
    var imports = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldLibraryView(
            controller: controller,
            callbacks: WorldLibraryCallbacks(
              onCreate: (name, seed, preset) async =>
                  created = (name: name, seed: seed, preset: preset),
              onImport: () async => imports++,
              onLoad: (entry) async {},
              onRename: (entry, name) async {},
              onDuplicate: (entry) async {},
              onDelete: (entry) async {},
              onReset: (entry) async {},
              onExport: (entry) async {},
              onShareSeed: (entry) async {},
            ),
            onClose: () {},
          ),
        ),
      ),
    );

    final node = tester.getSemantics(
      find.byKey(WorldLibraryKeys.card(world.id)),
    );
    expect(node.label, contains('World Beta Shore, seed 99'));

    await tester.tap(find.byKey(WorldLibraryKeys.importWorld));
    await tester.pumpAndSettle();
    expect(imports, 1);

    await tester.tap(find.byKey(WorldLibraryKeys.create));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Gamma Dunes');
    await tester.enterText(fields.at(1), '1234');
    final createButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Create'),
    );
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(created, (
      name: 'Gamma Dunes',
      seed: 1234,
      preset: WorldLibraryPreset.classic,
    ));
    semantics.dispose();
  });

  testWidgets('preset picker adapts and sends keyboard-selected value', (
    tester,
  ) async {
    _setViewport(tester, width: 360);
    final controller = WorldLibraryController();
    addTearDown(controller.dispose);
    ({String name, int? seed, WorldLibraryPreset preset})? created;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldLibraryView(
            controller: controller,
            callbacks: WorldLibraryCallbacks(
              onCreate: (name, seed, preset) async =>
                  created = (name: name, seed: seed, preset: preset),
              onImport: () async {},
              onLoad: (entry) async {},
              onRename: (entry, name) async {},
              onDuplicate: (entry) async {},
              onDelete: (entry) async {},
              onReset: (entry) async {},
              onExport: (entry) async {},
              onShareSeed: (entry) async {},
            ),
            onClose: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(WorldLibraryKeys.create));
    await tester.pumpAndSettle();
    expect(find.byType(RadioGroup<WorldLibraryPreset>), findsOneWidget);
    expect(find.byType(SegmentedButton<WorldLibraryPreset>), findsNothing);
    expect(
      tester.getSemantics(find.byKey(WorldLibraryKeys.createPresetGroup)).label,
      'World preset',
    );

    final flatRadio = tester.widget<RadioListTile<WorldLibraryPreset>>(
      find.byKey(WorldLibraryKeys.createPreset(WorldLibraryPreset.flat)),
    );
    final radioFocus = flatRadio.focusNode!;
    radioFocus.requestFocus();
    await tester.pump();
    expect(radioFocus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      tester
          .widget<RadioListTile<WorldLibraryPreset>>(
            find.byKey(
              WorldLibraryKeys.createPreset(WorldLibraryPreset.islands),
            ),
          )
          .selected,
      isTrue,
    );

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Flatland');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Create'),
      ),
    );
    await tester.pumpAndSettle();
    expect(created, (
      name: 'Flatland',
      seed: null,
      preset: WorldLibraryPreset.islands,
    ));
    semantics.dispose();
  });

  testWidgets('wide create dialog uses a segmented preset picker', (
    tester,
  ) async {
    _setViewport(tester, width: 800);
    final controller = WorldLibraryController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldLibraryView(
            controller: controller,
            callbacks: WorldLibraryCallbacks(
              onCreate: (name, seed, preset) async {},
              onImport: () async {},
              onLoad: (entry) async {},
              onRename: (entry, name) async {},
              onDuplicate: (entry) async {},
              onDelete: (entry) async {},
              onReset: (entry) async {},
              onExport: (entry) async {},
              onShareSeed: (entry) async {},
            ),
            onClose: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(WorldLibraryKeys.create));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<WorldLibraryPreset>), findsOneWidget);
    expect(find.byType(RadioGroup<WorldLibraryPreset>), findsNothing);
  });

  testWidgets('search field follows a replacement controller', (tester) async {
    _setViewport(tester, width: 800);
    final first = WorldLibraryController()..setQuery('first');
    final second = WorldLibraryController()..setQuery('second');
    final selected = ValueNotifier<WorldLibraryController>(first);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(selected.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<WorldLibraryController>(
          valueListenable: selected,
          builder: (context, controller, _) {
            return WorldLibraryView(
              controller: controller,
              callbacks: _emptyCallbacks,
              onClose: () {},
            );
          },
        ),
      ),
    );
    expect(
      tester
          .widget<TextField>(find.byKey(WorldLibraryKeys.search))
          .controller!
          .text,
      'first',
    );

    selected.value = second;
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(WorldLibraryKeys.search))
          .controller!
          .text,
      'second',
    );
  });
}

final _emptyCallbacks = WorldLibraryCallbacks(
  onCreate: (name, seed, preset) async {},
  onImport: () async {},
  onLoad: (entry) async {},
  onRename: (entry, name) async {},
  onDuplicate: (entry) async {},
  onDelete: (entry) async {},
  onReset: (entry) async {},
  onExport: (entry) async {},
  onShareSeed: (entry) async {},
);

Future<void> _chooseAction(
  WidgetTester tester,
  String worldId,
  String label,
) async {
  await tester.tap(find.byKey(WorldLibraryKeys.actions(worldId)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void _setViewport(
  WidgetTester tester, {
  required double width,
  double height = 900,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
