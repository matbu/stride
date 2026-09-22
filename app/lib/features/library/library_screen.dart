import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drafts.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../../data/session_actions.dart';
import '../planning/place_sheet.dart';
import '../planning/session_badge.dart';
import '../planning/session_editor.dart';
import 'import_screen.dart';

/// Bibliothèque de modèles : les séances préparées en amont, prêtes à être placées.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templates = ref.watch(templatesProvider).value ?? const <Template>[];
    final types = ref.watch(sessionTypesProvider).value ?? const <SessionType>[];
    final byId = {for (final t in types) t.id: t};
    final shown = _typeFilter == null ? templates : templates.where((t) => t.typeId == _typeFilter).toList();

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
        onPressed: () => openSessionEditor(context, newSessionDraft(template: true)),
        icon: const Icon(Icons.add),
        label: const Text('Modèle'),
      ),
      body: Column(
        children: [
          if (types.length > 1 && templates.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
          Expanded(
            child: shown.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 40),
                      Icon(Icons.library_books_outlined, size: 48, color: theme.colorScheme.outline),
                      const SizedBox(height: 12),
                      Text(
                        templates.isEmpty ? 'Ta bibliothèque est vide' : 'Aucun modèle de ce type',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        templates.isEmpty
                            ? 'Crée des séances en amont, puis place-les sur les jours de la semaine. '
                                'Tu peux aussi importer un fichier CSV.'
                            : 'Choisis un autre type ou crée un modèle.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final t = shown[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
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
                            ]),
                          ),
                          trailing: const Icon(Icons.more_vert),
                          onTap: () => _actions(t),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
