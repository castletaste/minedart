part of 'world_library.dart';

final class _WorldCard extends StatelessWidget {
  const _WorldCard({
    required this.world,
    required this.controller,
    required this.callbacks,
    required this.onAction,
  });

  final WorldLibraryEntry world;
  final WorldLibraryController controller;
  final WorldLibraryCallbacks callbacks;
  final ValueChanged<WorldLibraryAction> onAction;

  @override
  Widget build(BuildContext context) {
    final busy = controller.busyWorldId == world.id;
    return Semantics(
      key: WorldLibraryKeys.card(world.id),
      container: true,
      label: 'World ${world.name}, seed ${world.seed}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      world.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (world.isCurrent)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Chip(label: Text('Current')),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Seed ${world.seed}'),
              Text('Updated ${_formatWorldDate(world.updatedAt)}'),
              Text('MDRT${world.formatVersion}'),
              const Spacer(),
              if (busy) const LinearProgressIndicator(),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      key: WorldLibraryKeys.load(world.id),
                      onPressed: controller.isBusy
                          ? null
                          : () => unawaited(
                              controller.run(
                                world.id,
                                () => callbacks.onLoad(world),
                              ),
                            ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Load'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<WorldLibraryAction>(
                    key: WorldLibraryKeys.actions(world.id),
                    enabled: !controller.isBusy,
                    tooltip: 'Actions for ${world.name}',
                    onSelected: onAction,
                    itemBuilder: (context) =>
                        <PopupMenuEntry<WorldLibraryAction>>[
                          for (final action in WorldLibraryAction.values)
                            if (action != WorldLibraryAction.load)
                              PopupMenuItem<WorldLibraryAction>(
                                value: action,
                                child: Row(
                                  children: <Widget>[
                                    Icon(
                                      _worldActionIcon(action),
                                      color: action.isDestructive
                                          ? Theme.of(context).colorScheme.error
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(action.label),
                                  ],
                                ),
                              ),
                        ],
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _worldActionIcon(WorldLibraryAction action) => switch (action) {
  WorldLibraryAction.load => Icons.play_arrow,
  WorldLibraryAction.rename => Icons.edit_outlined,
  WorldLibraryAction.duplicate => Icons.copy_outlined,
  WorldLibraryAction.delete => Icons.delete_outline,
  WorldLibraryAction.reset => Icons.restart_alt,
  WorldLibraryAction.exportWorld => Icons.file_download_outlined,
  WorldLibraryAction.shareSeed => Icons.share_outlined,
};

String _formatWorldDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
