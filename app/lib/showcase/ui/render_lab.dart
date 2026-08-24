import 'package:flutter/material.dart';

import '../controller/render_lab_controller.dart';
import 'showcase_panel.dart';

abstract final class RenderLabKeys {
  static const debugView = ValueKey<String>('render-lab-debug-view');
  static const filtering = ValueKey<String>('render-lab-filtering');
  static const renderDistance = ValueKey<String>('render-lab-distance');
  static const fogDensity = ValueKey<String>('render-lab-fog-density');
  static const ambientOcclusion = ValueKey<String>('render-lab-ao');
  static const targetOutline = ValueKey<String>('render-lab-outline');
  static const blockParticles = ValueKey<String>('render-lab-particles');
  static const reset = ValueKey<String>('render-lab-reset');
}

final class RenderLabPanel extends StatelessWidget {
  const RenderLabPanel({required this.controller, super.key});

  final RenderLabController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final settings = controller.settings;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          ShowcasePanel(
            title: 'Render Lab',
            subtitle:
                'Live GPU uniforms, retained chunk visibility and frame data.',
            trailing: TextButton(
              key: RenderLabKeys.reset,
              onPressed: controller.reset,
              child: const Text('Reset'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DropdownButtonFormField<RenderDebugView>(
                  key: ValueKey<RenderDebugView>(settings.debugView),
                  initialValue: settings.debugView,
                  decoration: const InputDecoration(
                    labelText: 'Debug view',
                    prefixIcon: Icon(Icons.visibility_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<RenderDebugView>>[
                    for (final view in RenderDebugView.values)
                      DropdownMenuItem<RenderDebugView>(
                        value: view,
                        child: Text(view.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) controller.setDebugView(value);
                  },
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  key: RenderLabKeys.filtering,
                  decoration: const InputDecoration(
                    labelText: 'Texture filtering',
                    helperText:
                        'Nearest is fixed by the current flame_3d backend.',
                    prefixIcon: Icon(Icons.grid_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                  child: const Text('Nearest · backend capability'),
                ),
                const SizedBox(height: 12),
                LabeledSlider(
                  key: RenderLabKeys.renderDistance,
                  label: 'Render distance',
                  valueLabel: '${settings.renderDistance} chunks',
                  value: settings.renderDistance.toDouble(),
                  min: 2,
                  max: 16,
                  divisions: 14,
                  onChanged: controller.setRenderDistance,
                ),
                LabeledSlider(
                  key: RenderLabKeys.fogDensity,
                  label: 'Fog density',
                  valueLabel: '${(settings.fogDensity * 100).round()}%',
                  value: settings.fogDensity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: controller.setFogDensity,
                ),
                SwitchListTile(
                  key: RenderLabKeys.ambientOcclusion,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Baked lighting / ambient occlusion'),
                  value: settings.ambientOcclusion,
                  onChanged: controller.setAmbientOcclusion,
                ),
                SwitchListTile(
                  key: RenderLabKeys.targetOutline,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Target outline'),
                  value: settings.targetOutline,
                  onChanged: controller.setTargetOutline,
                ),
                SwitchListTile(
                  key: RenderLabKeys.blockParticles,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Block particles'),
                  value: settings.blockParticles,
                  onChanged: controller.setBlockParticles,
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
