import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drafts.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../../data/session_actions.dart';
import '../planning/place_sheet.dart';
import '../planning/session_badge.dart';
import '../planning/session_editor.dart';
import '../resources/add_resource.dart';
import '../resources/resource_widgets.dart';
import 'import_screen.dart';

/// Bibliothèque : les modèles de séance préparés en amont, prêts à être placés, et les
/// ressources du club (vidéos, liens, photos), chacun dans une liste dépliable.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String? _typeFilter;

  Future<void> _actions(Template t) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('tpl-place'),
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Placer sur un jour'),
              onTap: () => Navigator.pop(ctx, 'place'),
            ),
            ListTile(
              key: const Key('tpl-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Modifier'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              key: const Key('tpl-delete'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('Supprimer'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'place':
        await showPlaceSheet(context, template: t);
      case 'edit':
        await openSessionEditor(context, SessionDraft.fromTemplate(t));
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Supprimer le modèle ?'),
            content: Text('« ${t.title} » sera retiré de la bibliothèque. Les séances déjà placées '
                'ne sont pas modifiées.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
            ],
          ),
        );
        if (ok == true) await ref.read(sessionActionsProvider).delete(t.id);
    }
  }

  Future<void> _add() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('library-add-template'),
              leading: const Icon(Icons.fitness_center),
              title: const Text('Modèle de séance'),
              onTap: () => Navigator.pop(ctx, 'template'),
            ),
            ListTile(
              key: const Key('library-add-resource'),
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Ressource'),
              subtitle: const Text('Vidéo, lien YouTube / Instagram, photo'),
              onTap: () => Navigator.pop(ctx, 'resource'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'template') {
      await openSessionEditor(context, newSessionDraft(template: true));
    } else {
      await startAddResource(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templates = ref.watch(templatesProvider).value ?? const <Template>[];
    final types = ref.watch(sessionTypesProvider).value ?? const <SessionType>[];
    final resources = ref.watch(resourcesProvider).value ?? const <Resource>[];
    final byId = {for (final t in types) t.id: t};
    final shown = _typeFilter == null ? templates : templates.where((t) => t.typeId == _typeFilter).toList();
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bibliothèque'),
        actions: [
          IconButton(
            key: const Key('open-import'),
            tooltip: 'Importer un CSV',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ImportScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-template'),
        heroTag: 'library-new-template',
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          _Section(
            key: const Key('library-sessions'),
            icon: Icons.fitness_center,
            title: 'Séances',
            count: templates.length,
            children: [
              if (types.length > 1 && templates.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: ChoiceChip(
                          label: const Text('Tous'),
                          selected: _typeFilter == null,
                          onSelected: (_) => setState(() => _typeFilter = null),
                        ),
                      ),
                      for (final t in types)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: ChoiceChip(
                            label: Text(t.name),
                            selected: _typeFilter == t.id,
                            onSelected: (_) => setState(() => _typeFilter = t.id),
                          ),
                        ),
                    ],
                  ),
                ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    templates.isEmpty
                        ? 'Crée des séances en amont, puis place-les sur les jours de la semaine. '
                            'Tu peux aussi importer un fichier CSV.'
                        : 'Aucun modèle de ce type.',
                    style: muted,
                  ),
                ),
              for (final t in shown)
                ListTile(
                  key: Key('template-${t.title}'),
                  title: Text(t.title, style: theme.textTheme.titleMedium),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Flexible(child: TypeBadge(type: byId[t.typeId])),
                      if (t.durationMin != null) ...[
                        const SizedBox(width: 10),
                        Text('${t.durationMin} min'),
                      ],
                      if (t.resourceIds.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.attach_file, size: 16, color: theme.colorScheme.onSurfaceVariant),
                        Text('${t.resourceIds.length}'),
                      ],
                    ]),
                  ),
                  trailing: const Icon(Icons.more_vert),
                  onTap: () => _actions(t),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            key: const Key('library-resources'),
            icon: Icons.video_library_outlined,
            title: 'Ressources',
            count: resources.length,
            children: [
              if (resources.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    'Vidéos YouTube, reels Instagram, photos ou courtes vidéos : visibles par tout le club, '
                    'et attachables à une séance.',
                    style: muted,
                  ),
                ),
              ResourceList(resources: resources, manage: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// Liste dépliable de la bibliothèque (séances, ressources), ouverte par défaut.
class _Section extends StatelessWidget {
  const _Section({super.key, required this.icon, required this.title, required this.count, required this.children});
  final IconData icon;
  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(icon),
        title: Text('$title ($count)', style: Theme.of(context).textTheme.titleMedium),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: children,
      ),
    );
  }
}
