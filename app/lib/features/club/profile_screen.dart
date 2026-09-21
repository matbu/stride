import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../common.dart';

/// Profil d'un athlète : il choisit librement ses groupes d'entraînement.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final me = ref.watch(activeMembershipProvider);
    final club = ref.watch(clubProvider).value;
    final athlete = ref.watch(myAthleteProvider);
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final mine = athlete == null
        ? const <String>{}
        : (ref.watch(groupLinksProvider).value?[athlete.id] ?? const <String>{});

    if (me == null || club == null) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(me.displayName, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text('${me.role.label} · ${club.name}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SectionHeader('Mes groupes d’entraînement'),
          if (groups.isEmpty)
            const Text('Ton club n’a pas encore créé de groupe.')
          else ...[
            Text(
              'Choisis les groupes dont tu veux voir les séances.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in groups)
                  FilterChip(
                    key: Key('my-group-${g.name}'),
                    label: Text(g.name),
                    selected: mine.contains(g.id),
                    onSelected: athlete == null
                        ? null
                        : (on) => ref.read(planningActionsProvider).setGroupMembership(
                              clubId: club.id,
                              athlete: athlete,
                              groupId: g.id,
                              member: on,
                            ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 32),
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Quitter ${club.name} ?'),
                  content: const Text('Tu n’auras plus accès aux séances du club.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitter')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await guarded(context, () => ref.read(clubActionsProvider).leaveClub(club.id));
              }
            },
            child: const Text('Quitter le club'),
          ),
          TextButton(
            onPressed: () => confirmSignOut(context, ref),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }
}
