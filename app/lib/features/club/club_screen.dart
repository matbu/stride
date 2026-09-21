import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../common.dart';
import 'invite_dialog.dart';

/// Gestion du club par les coachs : demandes, groupes, athlètes, coachs, invitations.
class ClubScreen extends ConsumerWidget {
  const ClubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(activeMembershipProvider);
    final club = ref.watch(clubProvider).value;
    if (me == null || club == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isOwner = me.role == ClubRole.owner;
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final athletes = ref.watch(athletesProvider).value ?? const <Athlete>[];
    final links =
        ref.watch(groupLinksProvider).value ?? const <String, Set<String>>{};
    final members = ref.watch(membersProvider).value ?? const <Membership>[];
    final requests =
        ref.watch(pendingRequestsProvider).value ?? const <Membership>[];
    final coaches = members.where((m) => m.role.isCoach).toList()
      ..sort(
        (a, b) => a.role == b.role
            ? a.displayName.compareTo(b.displayName)
            : a.role.index - b.role.index,
      );

    return Scaffold(
      appBar: AppBar(title: Text(club.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(me.role.label, style: Theme.of(context).textTheme.labelLarge),
          if (requests.isNotEmpty) ...[
            const SectionHeader('Demandes en attente'),
            for (final r in requests)
              _gap(
                _RequestTile(
                  request: r,
                  canDecide: r.role == ClubRole.athlete || isOwner,
                ),
              ),
          ],
          SectionHeader(
            'Groupes',
            trailing: TextButton.icon(
              key: const Key('add-group'),
              onPressed: () => _addGroup(context, ref, club.id),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
          ),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Aucun groupe. Crée un premier groupe pour pouvoir placer des séances.',
              ),
            ),
          for (final g in groups)
            _gap(
              Card(
                child: ListTile(
                  title: Text(g.name),
                  subtitle: Text(
                    _count(
                      links.values.where((s) => s.contains(g.id)).length,
                      'athlète',
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (_) =>
                        ref.read(planningActionsProvider).archiveGroup(g.id),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'archive',
                        child: Text('Archiver le groupe'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SectionHeader(
            'Athlètes',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      _inviteMany(context, ref, club, ClubRole.athlete),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Inviter'),
                ),
                TextButton.icon(
                  key: const Key('add-athlete'),
                  onPressed: () => _addAthlete(context, ref, club.id),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                ),
              ],
            ),
          ),
          if (athletes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Aucun athlète pour le moment. Les groupes peuvent rester vides.',
              ),
            ),
          for (final a in athletes)
            _gap(
              Card(
                child: ListTile(
                  title: Text(a.fullName),
                  subtitle: Text(
                    '${a.hasAccount ? 'Compte lié' : 'Pas encore de compte'} · ${_count(links[a.id]?.length ?? 0, 'groupe')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _athleteSheet(context, club, a),
                ),
              ),
            ),
          SectionHeader(
            'Coachs',
            trailing: isOwner
                ? TextButton.icon(
                    onPressed: () => _inviteCoach(context, ref, club),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Inviter'),
                  )
                : null,
          ),
          for (final c in coaches)
            _gap(
              Card(
                child: ListTile(
                  title: Text(c.displayName),
                  subtitle: Text(c.role.label),
                  trailing: (isOwner && c.role == ClubRole.coach)
                      ? PopupMenuButton<String>(
                          onSelected: (v) => v == 'transfer'
                              ? _transfer(context, ref, club, c)
                              : _remove(context, ref, club.id, c),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'transfer',
                              child: Text('Passer le rôle de super coach'),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Retirer du club'),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
            ),
          const SizedBox(height: 24),
          if (!isOwner)
            TextButton(
              onPressed: () => _leave(context, ref, club),
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

  /// Espace entre deux cartes de liste.
  static Widget _gap(Widget card) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: card);

  static String _count(int n, String noun) => '$n $noun${n > 1 ? 's' : ''}';

  Future<String?> _askName(BuildContext context, String title, String label) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('name-field'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('name-ok'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _addGroup(
    BuildContext context,
    WidgetRef ref,
    String clubId,
  ) async {
    final name = await _askName(context, 'Nouveau groupe', 'Nom du groupe');
    if (name == null || name.isEmpty) return;
    await ref.read(planningActionsProvider).addGroup(clubId, name);
  }

  Future<void> _addAthlete(
    BuildContext context,
    WidgetRef ref,
    String clubId,
  ) async {
    final name = await _askName(context, 'Nouvel athlète', 'Prénom et nom');
    if (name == null || name.isEmpty) return;
    await ref.read(planningActionsProvider).addAthlete(clubId, name);
  }

  Future<void> _inviteMany(
    BuildContext context,
    WidgetRef ref,
    Club club,
    ClubRole role,
  ) async {
    final code = await guarded(
      context,
      () => ref
          .read(clubActionsProvider)
          .createInvitation(club.id, role, maxUses: null),
    );
    if (code != null && context.mounted) {
      await showInviteDialog(
        context,
        code: code,
        clubName: club.name,
        role: role,
      );
    }
  }

  Future<void> _inviteCoach(
    BuildContext context,
    WidgetRef ref,
    Club club,
  ) async {
    final code = await guarded(
      context,
      () => ref
          .read(clubActionsProvider)
          .createInvitation(club.id, ClubRole.coach),
    );
    if (code != null && context.mounted) {
      await showInviteDialog(
        context,
        code: code,
        clubName: club.name,
        role: ClubRole.coach,
      );
    }
  }

  Future<void> _athleteSheet(BuildContext context, Club club, Athlete athlete) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _AthleteSheet(club: club, athleteId: athlete.id),
    );
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String body,
    String action,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _transfer(
    BuildContext context,
    WidgetRef ref,
    Club club,
    Membership coach,
  ) async {
    final ok = await _confirm(
      context,
      'Passer le rôle de super coach ?',
      '${coach.displayName} deviendra super coach de ${club.name}. Tu deviendras coach.',
      'Confirmer',
    );
    if (ok && context.mounted) {
      await guarded(
        context,
        () => ref
            .read(clubActionsProvider)
            .transferOwnership(club.id, coach.userId),
      );
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    String clubId,
    Membership m,
  ) async {
    final ok = await _confirm(
      context,
      'Retirer ${m.displayName} ?',
      'Cette personne perdra l’accès au club.',
      'Retirer',
    );
    if (ok && context.mounted) {
      await guarded(
        context,
        () => ref.read(clubActionsProvider).removeMember(clubId, m.userId),
      );
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, Club club) async {
    final ok = await _confirm(
      context,
      'Quitter ${club.name} ?',
      'Tu n’auras plus accès aux séances du club.',
      'Quitter',
    );
    if (ok && context.mounted) {
      await guarded(
        context,
        () => ref.read(clubActionsProvider).leaveClub(club.id),
      );
    }
  }
}

class _RequestTile extends ConsumerWidget {
  const _RequestTile({required this.request, required this.canDecide});
  final Membership request;
  final bool canDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(request.displayName),
        subtitle: Text(
          canDecide
              ? 'Souhaite rejoindre en tant que ${request.role.label.toLowerCase()}'
              : 'Demande coach : seul le super coach peut la valider',
        ),
        trailing: canDecide
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Refuser',
                    icon: const Icon(Icons.close),
                    onPressed: () => guarded(
                      context,
                      () => ref.read(clubActionsProvider).reject(request.id),
                    ),
                  ),
                  IconButton.filled(
                    key: Key('approve-${request.displayName}'),
                    tooltip: 'Accepter',
                    icon: const Icon(Icons.check),
                    onPressed: () => guarded(
                      context,
                      () => ref.read(clubActionsProvider).approve(request.id),
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _AthleteSheet extends ConsumerWidget {
  const _AthleteSheet({required this.club, required this.athleteId});
  final Club club;
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final athlete = (ref.watch(athletesProvider).value ?? const <Athlete>[])
        .where((a) => a.id == athleteId)
        .firstOrNull;
    if (athlete == null) return const SizedBox(height: 120);
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final mine =
        ref.watch(groupLinksProvider).value?[athlete.id] ?? const <String>{};

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(athlete.fullName, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Text('Groupes', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (groups.isEmpty) const Text('Aucun groupe pour le moment.'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in groups)
                FilterChip(
                  label: Text(g.name),
                  selected: mine.contains(g.id),
                  onSelected: (on) => ref
                      .read(planningActionsProvider)
                      .setGroupMembership(
                        clubId: club.id,
                        athlete: athlete,
                        groupId: g.id,
                        member: on,
                      ),
                ),
            ],
          ),
          if (!athlete.hasAccount) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: const Text('Inviter cet athlète'),
              onPressed: () async {
                final code = await guarded(
                  context,
                  () => ref
                      .read(clubActionsProvider)
                      .createInvitation(
                        club.id,
                        ClubRole.athlete,
                        athleteId: athlete.id,
                      ),
                );
                if (code != null && context.mounted) {
                  await showInviteDialog(
                    context,
                    code: code,
                    clubName: club.name,
                    role: ClubRole.athlete,
                    forName: athlete.fullName,
                  );
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
