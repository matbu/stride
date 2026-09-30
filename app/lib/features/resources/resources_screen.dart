import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/queries.dart';
import 'add_resource.dart';
import 'resource_widgets.dart';

/// Ressources du club en plein écran : consultation pour un athlète (qui n'a pas l'onglet
/// bibliothèque), gestion complète pour un coach.
class ResourcesScreen extends ConsumerWidget {
  const ResourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isCoach = ref.watch(isCoachProvider);
    final resources = ref.watch(resourcesProvider).value ?? const <Resource>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Ressources du club')),
      floatingActionButton: isCoach
          ? FloatingActionButton.extended(
              heroTag: 'resources-add',
              onPressed: () => startAddResource(context),
              icon: const Icon(Icons.add),
              label: const Text('Ressource'),
            )
          : null,
      body: resources.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  isCoach
                      ? 'Aucune ressource. Ajoute une vidéo, un lien ou une photo.'
                      : 'Tes coachs n’ont pas encore partagé de ressource.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              children: [ResourceList(resources: resources, manage: isCoach)],
            ),
    );
  }
}
