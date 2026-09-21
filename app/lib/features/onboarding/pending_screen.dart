import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/actions.dart';
import '../../data/database.dart';
import '../../data/queries.dart';
import '../common.dart';

/// Nom du club d'une demande en attente. Lu en ligne : les données d'un club ne sont pas
/// synchronisées tant qu'on n'en est pas membre actif.
final pendingClubNameProvider = FutureProvider.family<String?, String>((ref, clubId) async {
  final row = await ref
      .watch(supabaseProvider)
      .from('clubs')
      .select('name')
      .eq('id', clubId)
      .maybeSingle();
  return row?['name'] as String?;
});

class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pending = ref.watch(pendingMembershipProvider);
    final clubName = pending == null ? null : ref.watch(pendingClubNameProvider(pending.clubId)).value;

    return FormPage(
      children: [
        const SizedBox(height: 48),
        Icon(Icons.hourglass_top_rounded, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 20),
        Text(
          'Demande envoyée',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          clubName == null
              ? 'Un coach du club doit valider ta demande.'
              : 'Un coach de $clubName doit valider ta demande. Tu entreras dans le club dès qu’il l’aura fait.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        if (pending != null)
          OutlinedButton(
            onPressed: () => guarded(
              context,
              () => ref.read(clubActionsProvider).leaveClub(pending.clubId),
            ),
            child: const Text('Annuler ma demande'),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => confirmSignOut(context, ref),
          child: const Text('Se déconnecter'),
        ),
      ],
    );
  }
}
