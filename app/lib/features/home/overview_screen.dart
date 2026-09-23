import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../common.dart';
import '../planning/navigation.dart';
import '../planning/session_card.dart';

/// Accueil : la ou les séances du jour (« Repos » sinon), et pour un coach la présence à
/// l'entraînement par groupe — prise directement ici, consultable ensuite depuis la fiche de
/// chaque athlète (voir `_AthleteProfilePreview` dans club_screen.dart).
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isCoach = ref.watch(isCoachProvider);
    final club = ref.watch(clubProvider).value;
    final today = dateOnly(DateTime.now());
    final todayIso = isoDate(today);
    final types = {for (final t in ref.watch(sessionTypesProvider).value ?? const <SessionType>[]) t.id: t};
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final groupNames = {for (final g in groups) g.id: g.name};
    final athletes = ref.watch(athletesProvider).value ?? const <Athlete>[];
    final groupLinks = ref.watch(groupLinksProvider).value ?? const <String, Set<String>>{};
    final allToday = ref.watch(sessionsForRangeProvider('$todayIso|$todayIso')).value ?? const <PlannedSession>[];

    final attendance = ref.watch(attendanceForDateProvider(todayIso)).value ?? const <String, Set<String>>{};
    final myAthlete = ref.watch(myAthleteProvider);
    final sessionsToShow = isCoach
        ? allToday
        : myAthlete == null
            ? const <PlannedSession>[]
            : allToday.where((s) => (groupLinks[myAthlete.id] ?? const <String>{}).contains(s.groupId)).toList();

    void open(PlannedSession s) => openSession(
          context,
          s,
          isCoach: isCoach,
          type: types[s.typeId],
          groupName: groupNames[s.groupId],
        );

    void toggleAttendance(String groupId, String athleteId, bool present) {
      if (club == null) return;
      guarded(
        context,
        () => ref.read(planningActionsProvider).setAttendance(
              clubId: club.id,
              groupId: groupId,
              athleteId: athleteId,
              date: todayIso,
              present: present,
            ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/images/logo.png', width: 28, height: 28),
            ),
            const SizedBox(width: 10),
            const Text('TrackClub'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(longDayLabel(today), style: theme.textTheme.titleMedium),
          const SectionHeader('Séance du jour'),
          if (sessionsToShow.isEmpty)
            _RestCard(coach: isCoach)
          else
            for (final s in sessionsToShow)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SessionCard(
                  session: s,
                  type: types[s.typeId],
                  groupName: groupNames[s.groupId],
                  onTap: () => open(s),
                ),
              ),
          if (isCoach) ...[
            const SectionHeader('Présence à l’entraînement'),
            if (groups.isEmpty) const Text('Crée un groupe pour pouvoir prendre les présences.'),
            for (final g in groups)
              _GroupAttendanceCard(
                key: Key('attendance-group-${g.name}'),
                group: g,
                athletes: athletes.where((a) => (groupLinks[a.id] ?? const <String>{}).contains(g.id)).toList(),
                present: attendance[g.id] ?? const <String>{},
                onToggle: (athleteId, value) => toggleAttendance(g.id, athleteId, value),
              ),
          ],
        ],
      ),
    );
  }
}

class _RestCard extends StatelessWidget {
  const _RestCard({required this.coach});
  final bool coach;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.self_improvement, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('Repos', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              coach ? 'Aucune séance placée aujourd’hui.' : 'Rien de prévu pour toi aujourd’hui.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupAttendanceCard extends StatelessWidget {
  const _GroupAttendanceCard({
    super.key,
    required this.group,
    required this.athletes,
    required this.present,
    required this.onToggle,
  });

  final Group group;
  final List<Athlete> athletes;
  final Set<String> present;
  final void Function(String athleteId, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(group.name),
        subtitle: Text('${present.length}/${athletes.length} présent${present.length > 1 ? 's' : ''}'),
        children: [
          if (athletes.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(alignment: Alignment.centerLeft, child: Text('Aucun athlète dans ce groupe.')),
            ),
          for (final a in athletes)
            CheckboxListTile(
              key: Key('present-${a.fullName}'),
              title: Text(a.fullName),
              value: present.contains(a.id),
              onChanged: (v) => onToggle(a.id, v ?? false),
            ),
        ],
      ),
    );
  }
}
