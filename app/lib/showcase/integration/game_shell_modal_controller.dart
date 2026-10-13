import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../controller/builder_studio_controller.dart';
import '../controller/options_controller.dart';
import '../controller/render_lab_controller.dart';
import '../controller/world_library_controller.dart';
import '../ui/builder_studio.dart';
import '../ui/modal_input_region.dart';
import '../ui/pause_options.dart';
import '../ui/render_lab.dart';
import '../ui/world_library.dart';
import 'modal_input_controller.dart';
import 'world_library_actions.dart';
import 'world_session_coordinator.dart';

/// Owns the modal route workflows used by [GameShell].
///
/// The shell remains responsible for widget lifetime and state publication;
/// this controller keeps route transitions, input capture, and save-before-
/// library behavior out of the host build method.
final class GameShellModalController {
  GameShellModalController({
    required this.navigatorContext,
    required this.modalInput,
    required this.builder,
    required this.options,
    required this.renderLab,
    required this.touchControls,
    required this.worldLibrary,
    required this.libraryActions,
    required this.session,
    required this.refreshWorlds,
    required this.launch,
    required this.onTouchControlsChanged,
  });

  final BuildContext? Function() navigatorContext;
  final ModalInputController modalInput;
  final BuilderStudioController builder;
  final OptionsController options;
  final RenderLabController renderLab;
  final ValueListenable<bool> touchControls;
  final WorldLibraryController worldLibrary;
  final WorldLibraryActions libraryActions;
  final WorldSessionCoordinator session;
  final Future<void> Function() refreshWorlds;
  final void Function(Future<void> action) launch;
  final void Function(bool enabled) onTouchControlsChanged;

  bool _savingAndQuitting = false;

  Future<void> showBuilder() async {
    final modalContext = navigatorContext();
    if (!_canOpenModal(modalContext)) return;
    final context = modalContext!;
    await modalInput.run(() async {
      if (!context.mounted) return;
      await showBuilderStudio(
        context,
        controller: builder,
        closeKey: options.bindingFor(GameInputAction.openInventory),
        onInputCaptureChanged: modalInput.inputCaptureChanged,
      );
    });
  }

  Future<void> showPauseOptions() async {
    final modalContext = navigatorContext();
    if (!_canOpenModal(modalContext)) return;
    final context = modalContext!;
    await modalInput.run(() async {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        requestFocus: true,
        builder: (dialogContext) => Dialog.fullscreen(
          backgroundColor: Colors.transparent,
          child: ValueListenableBuilder<bool>(
            valueListenable: touchControls,
            builder: (context, touchEnabled, _) => PauseOptionsView(
              controller: options,
              touchControls: touchEnabled,
              onTouchControlsChanged: onTouchControlsChanged,
              onInputCaptureChanged: modalInput.inputCaptureChanged,
              callbacks: PauseMenuCallbacks(
                onResume: () => Navigator.of(dialogContext).pop(),
                onOpenWorldLibrary: () =>
                    _transitionModal(dialogContext, showWorldLibrary),
                onOpenRenderLab: () =>
                    _transitionModal(dialogContext, showRenderLab),
                onSaveAndQuit: () => launch(saveAndOpenLibrary(dialogContext)),
              ),
            ),
          ),
        ),
      );
    }, pauseSimulation: true);
  }

  Future<void> showRenderLab() => showPanel(
    title: 'Render Lab',
    child: RenderLabPanel(controller: renderLab),
  );

  Future<void> showPanel({required String title, required Widget child}) async {
    final modalContext = navigatorContext();
    if (!_canOpenModal(modalContext)) return;
    final context = modalContext!;
    await modalInput.run(() async {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        requestFocus: true,
        builder: (dialogContext) => ModalInputRegion(
          onInputCaptureChanged: modalInput.inputCaptureChanged,
          child: Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
              child: Column(
                children: [
                  ListTile(
                    title: Text(title),
                    trailing: IconButton(
                      tooltip: 'Close $title',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Future<void> showWorldLibrary() async {
    final modalContext = navigatorContext();
    if (!_canOpenModal(modalContext)) return;
    await modalInput.run(() async {
      await refreshWorlds();
      final context = navigatorContext();
      if (context == null || !context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        requestFocus: true,
        builder: (dialogContext) => Dialog.fullscreen(
          child: WorldLibraryView(
            controller: worldLibrary,
            autofocusSearch: !touchControls.value,
            callbacks: libraryActions.callbacks(
              onActivated: () {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
            ),
            onClose: () => Navigator.of(dialogContext).pop(),
            onInputCaptureChanged: modalInput.inputCaptureChanged,
          ),
        ),
      );
    });
  }

  Future<void> saveAndOpenLibrary(BuildContext dialogContext) async {
    if (_savingAndQuitting) return;
    _savingAndQuitting = true;
    try {
      final result = await session.saveCurrent();
      if (result is WorldSessionFailure<void>) {
        throw WorldSessionException.fromFailure(result);
      }
      if (result is WorldSessionSuccess<void> && dialogContext.mounted) {
        _transitionModal(dialogContext, showWorldLibrary);
      }
    } finally {
      _savingAndQuitting = false;
    }
  }

  void _transitionModal(
    BuildContext dialogContext,
    Future<void> Function() to,
  ) {
    Navigator.of(dialogContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => launch(to()));
  }

  bool _canOpenModal(BuildContext? context) =>
      context != null && context.mounted && !modalInput.isOpen;
}
