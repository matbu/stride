import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/event_actions.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../common.dart';

/// Calendrier de saison : compétitions, échéances, stages. Visible par tout le club (filtré à
/// « tout le club » ou aux groupes concernés selon `event_groups`) ; création/modification/
/// suppression réservées aux coachs.
class SeasonScreen extends ConsumerWidget {
  const SeasonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isCoach = ref.watch(isCoachProvider);
    final events = ref.watch(eventsForClubProvider).value ?? const <Event>[];
    final eventGroups =
        ref.watch(eventGroupsProvider).value ?? const <String, Set<String>>{};
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final groupNames = {for (final g in groups) g.id: g.name};
    final todayIso = isoDate(dateOnly(DateTime.now()));

    // Comparaison lexicographique : les dates sont en ISO (`yyyy-MM-dd`), donc l'ordre textuel
    // correspond à l'ordre chronologique.
    final upcoming = events
        .where((e) => e.endDate.compareTo(todayIso) >= 0)
        .toList();
    final past = events
        .where((e) => e.endDate.compareTo(todayIso) < 0)
        .toList()
        .reversed
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Saison')),
      floatingActionButton: isCoach
          ? FloatingActionButton.extended(
              key: const Key('add-event'),
              onPressed: () => _openEditor(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            )
          : null,
      body: (upcoming.isEmpty && past.isEmpty)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  isCoach
                      ? 'Aucun événement pour le moment. Ajoute une compétition, une échéance ou un stage.'
                      : 'Aucun événement pour le moment.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (upcoming.isNotEmpty) const SectionHeader('À venir'),
                for (final e in upcoming)
                  _EventCard(
                    event: e,
                    groupNames: [
                      for (final id in eventGroups[e.id] ?? const <String>{})
                        ?groupNames[id],
                    ],
                    onTap: () => isCoach
                        ? _openEditor(context, ref, existing: e)
                        : _openDetail(context, e, groupNames, eventGroups),
                  ),
                if (past.isNotEmpty) const SectionHeader('Passés'),
                for (final e in past)
                  Opacity(
                    opacity: 0.6,
                    child: _EventCard(
                      event: e,
                      groupNames: [
                        for (final id in eventGroups[e.id] ?? const <String>{})
                          ?groupNames[id],
                      ],
                      onTap: () => isCoach
                          ? _openEditor(context, ref, existing: e)
                          : _openDetail(context, e, groupNames, eventGroups),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    Event? existing,
  }) {
    final clubId = ref.read(clubIdProvider);
    if (clubId == null) return Future.value();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EventEditorSheet(clubId: clubId, existing: existing),
    );
  }

  Future<void> _openDetail(
    BuildContext context,
    Event e,
    Map<String, String> groupNames,
    Map<String, Set<String>> eventGroups,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EventDetailSheet(
        event: e,
        groupNames: [
          for (final id in eventGroups[e.id] ?? const <String>{})
            ?groupNames[id],
        ],
      ),
    );
  }
}

IconData _kindIcon(EventKind k) => switch (k) {
  EventKind.competition => Icons.emoji_events_outlined,
  EventKind.deadline => Icons.event_busy_outlined,
  EventKind.camp => Icons.terrain_outlined,
  EventKind.other => Icons.event_note_outlined,
};

/// « 10 oct. 2026 » pour un événement d'un jour, « 10 → 12 oct. 2026 » sur plusieurs jours.
String _dateRangeLabel(Event e) {
  final start = parseIsoDate(e.startDate);
  final end = parseIsoDate(e.endDate);
  if (e.startDate == e.endDate) return mediumDate(start);
  return '${mediumDate(start)} → ${mediumDate(end)}';
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.groupNames,
    required this.onTap,
  });
  final Event event;
  final List<String> groupNames;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = [
      _dateRangeLabel(event),
      if (event.location.isNotEmpty) event.location,
      groupNames.isEmpty ? 'Tout le club' : groupNames.join(', '),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Icon(_kindIcon(event.kind))),
        title: Text(event.title),
        subtitle: Text(subtitleParts.join(' · ')),
        trailing: event.priority == null
            ? null
            : CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  event.priority!.dbValue,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
        onTap: onTap,
      ),
    );
  }
}

/// Vue lecture seule pour un athlète : le détail complet (notes incluses), pas de modification.
class _EventDetailSheet extends StatelessWidget {
  const _EventDetailSheet({required this.event, required this.groupNames});
  final Event event;
  final List<String> groupNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_kindIcon(event.kind), color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(event.title, style: theme.textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(event.kind.label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 12),
          Text(_dateRangeLabel(event)),
          if (event.location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(event.location),
          ],
          const SizedBox(height: 4),
          Text(groupNames.isEmpty ? 'Tout le club' : groupNames.join(', ')),
          if (event.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(event.notes, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Création ou modification d'un événement (coach uniquement).
class _EventEditorSheet extends ConsumerStatefulWidget {
  const _EventEditorSheet({required this.clubId, this.existing});
  final String clubId;
  final Event? existing;

  @override
  ConsumerState<_EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends ConsumerState<_EventEditorSheet> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _location = TextEditingController(
    text: widget.existing?.location ?? '',
  );
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late EventKind _kind = widget.existing?.kind ?? EventKind.competition;
  late EventPriority? _priority = widget.existing?.priority;
  late DateTime _start = widget.existing == null
      ? dateOnly(DateTime.now())
      : parseIsoDate(widget.existing!.startDate);
  late DateTime _end = widget.existing == null
      ? dateOnly(DateTime.now())
      : parseIsoDate(widget.existing!.endDate);
  Set<String>? _groupIds; // null tant que non initialisé depuis le flux ; ensuite, la main de l'utilisateur.
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _valid => _title.text.trim().isNotEmpty && !_end.isBefore(_start);

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = dateOnly(picked);
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = dateOnly(picked);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      await ref
          .read(eventActionsProvider)
          .save(
            id: widget.existing?.id,
            clubId: widget.clubId,
            kind: _kind,
            title: _title.text,
            startDate: isoDate(_start),
            endDate: isoDate(_end),
            location: _location.text,
            priority: _priority,
            notes: _notes.text,
            groupIds: _groupIds ?? const {},
          );
      return true;
    });
    if (!mounted) return;
    if (ok == true) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet événement ?'),
        content: Text(
          '« ${widget.existing!.title} » sera supprimé pour tout le club.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await guarded(
      context,
      () => ref.read(eventActionsProvider).delete(widget.existing!.id),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    if (_groupIds == null && widget.existing != null) {
      final linked = ref.watch(eventGroupsProvider).value?[widget.existing!.id];
      if (linked != null) _groupIds = {...linked};
    }
    final selectedGroups = _groupIds ?? const <String>{};
    final wholeClub = selectedGroups.isEmpty;

    // Un formulaire aussi long que celui-ci dépasse la hauteur de l'écran : sans cette borne,
    // `showModalBottomSheet` laisse le contenu grandir librement (le `SingleChildScrollView`
    // n'a alors rien à borner, et le bas du formulaire finit hors écran).
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null
                    ? 'Nouvel événement'
                    : 'Modifier l’événement',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('event-title'),
                controller: _title,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Titre',
                  hintText: 'Régionaux, dossier CACI…',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in EventKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_outlined),
                      label: Text(mediumDate(_start)),
                      onPressed: () => _pickDate(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('→'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_outlined),
                      label: Text(mediumDate(_end)),
                      onPressed: () => _pickDate(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('event-location'),
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'Lieu (facultatif)',
                ),
              ),
              const SizedBox(height: 16),
              Text('Priorité (facultatif)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Aucune'),
                    selected: _priority == null,
                    onSelected: (_) => setState(() => _priority = null),
                  ),
                  for (final p in EventPriority.values)
                    ChoiceChip(
                      label: Text(p.dbValue),
                      selected: _priority == p,
                      onSelected: (_) => setState(() => _priority = p),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Groupes concernés', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Tout le club'),
                    selected: wholeClub,
                    onSelected: (_) => setState(() => _groupIds = {}),
                  ),
                  for (final g in groups)
                    FilterChip(
                      key: Key('event-group-${g.name}'),
                      label: Text(g.name),
                      selected: selectedGroups.contains(g.id),
                      onSelected: (on) => setState(() {
                        final next = {...selectedGroups};
                        on ? next.add(g.id) : next.remove(g.id);
                        _groupIds = next;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('event-notes'),
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (facultatif)',
                ),
              ),
              const SizedBox(height: 20),
              // Un bouton Material posé directement à côté d'un autre dans un `Row` (même avec
              // `Expanded`) fait planter le layout de cette version de Flutter (mesure interne à
              // largeur non bornée de `ButtonStyleButton`) : les deux boutons sont donc l'un sous
              // l'autre plutôt que côte à côte.
              if (widget.existing != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: _busy ? null : _delete,
                    child: const Text('Supprimer'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('event-save'),
                  onPressed: (_busy || !_valid) ? null : _save,
                  child: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
