import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../../data/session_actions.dart';
import '../common.dart';
import 'navigation.dart';
import 'session_card.dart';

/// Largeur à partir de laquelle on affiche les 7 jours côte à côte (tablette, paysage).
const weekColumnsMinWidth = 720.0;

/// Vue semaine.
///  * Téléphone : bande des 7 jours (pastilles de couleur par type) et agenda du jour
///    sélectionné ; glisser horizontalement change de jour.
///  * Tablette : 7 colonnes. Un coach déplace une séance vers un autre jour en la
///    maintenant appuyée puis en la glissant.
class WeekScreen extends ConsumerStatefulWidget {
  const WeekScreen({super.key});

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  DateTime _selected = dateOnly(DateTime.now());
  String? _groupFilter; // null = tous les groupes

  DateTime get _monday => mondayOf(_selected);

  void _shiftDays(int n) => setState(() => _selected = addDays(_selected, n));

  @override
  Widget build(BuildContext context) {
    final isCoach = ref.watch(isCoachProvider);
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final types = {for (final t in ref.watch(sessionTypesProvider).value ?? const <SessionType>[]) t.id: t};
    final groupNames = {for (final g in groups) g.id: g.name};
    final all = ref.watch(sessionsForWeekProvider(isoDate(_monday))).value ?? const <PlannedSession>[];
    final sessions = _groupFilter == null ? all : all.where((s) => s.groupId == _groupFilter).toList();
    final today = dateOnly(DateTime.now());

    void open(PlannedSession s) => openSession(
          context,
          s,
          isCoach: isCoach,
          type: types[s.typeId],
          groupName: groupNames[s.groupId],
        );

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= weekColumnsMinWidth;
      return Scaffold(
        appBar: AppBar(
          title: Text(weekRangeLabel(_monday)),
          actions: [
            if (_selected != today)
              TextButton(
                onPressed: () => setState(() => _selected = today),
                child: const Text('Aujourd’hui'),
              ),
            IconButton(
              tooltip: 'Semaine précédente',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shiftDays(-7),
            ),
            IconButton(
              tooltip: 'Semaine suivante',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _shiftDays(7),
            ),
          ],
        ),
        floatingActionButton: isCoach
            ? FloatingActionButton.extended(
                key: const Key('add-session'),
                onPressed: () => startNewSession(context, date: _selected, groupId: _groupFilter),
                icon: const Icon(Icons.add),
                label: const Text('Séance'),
              )
            : null,
        body: Column(
          children: [
            if (!wide)
              _DayStrip(
                monday: _monday,
                selected: _selected,
                today: today,
                sessions: sessions,
                types: types,
                onSelect: (d) => setState(() => _selected = d),
              ),
            if (isCoach && groups.length > 1)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _FilterChip(label: 'Tous', selected: _groupFilter == null, onTap: () => setState(() => _groupFilter = null)),
                    for (final g in groups)
                      _FilterChip(
                        label: g.name,
                        selected: _groupFilter == g.id,
                        onTap: () => setState(() => _groupFilter = g.id),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: wide
                  ? _WeekColumns(
                      monday: _monday,
                      today: today,
                      sessions: sessions,
                      types: types,
                      groupNames: groupNames,
                      isCoach: isCoach,
                      onOpen: open,
                      onAdd: (d) => startNewSession(context, date: d, groupId: _groupFilter),
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() > 300) _shiftDays(v < 0 ? 1 : -1);
                      },
                      child: _DayAgenda(
                        day: _selected,
                        sessions: sessions.where((s) => s.date == isoDate(_selected)).toList(),
                        types: types,
                        groupNames: groupNames,
                        isCoach: isCoach,
                        onOpen: open,
                        onAdd: () => startNewSession(context, date: _selected, groupId: _groupFilter),
                      ),
                    ),
            ),
          ],
        ),
      );
    });
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

// --- Téléphone -----------------------------------------------------------------------------

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.monday,
    required this.selected,
    required this.today,
    required this.sessions,
    required this.types,
    required this.onSelect,
  });

  final DateTime monday;
  final DateTime selected;
  final DateTime today;
  final List<PlannedSession> sessions;
  final Map<String, SessionType> types;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++) Expanded(child: _dayCell(theme, addDays(monday, i))),
        ],
      ),
    );
  }

  Widget _dayCell(ThemeData theme, DateTime day) {
    final isSelected = day == selected;
    final isToday = day == today;
    final colors = <Color>{
      for (final s in sessions)
        if (s.date == isoDate(day)) (types[s.typeId]?.color ?? theme.colorScheme.outline),
    }.take(4).toList();

    return Semantics(
      selected: isSelected,
      label: longDayLabel(day),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onSelect(day),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Text(
                weekdayLetter(day),
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? theme.colorScheme.primary : null,
                  border: (isToday && !isSelected) ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
                ),
                child: Text(
                  '${day.day}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isSelected ? theme.colorScheme.onPrimary : null,
                    fontWeight: (isSelected || isToday) ? FontWeight.w700 : null,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in colors)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({
    required this.day,
    required this.sessions,
    required this.types,
    required this.groupNames,
    required this.isCoach,
    required this.onOpen,
    required this.onAdd,
  });

  final DateTime day;
  final List<PlannedSession> sessions;
  final Map<String, SessionType> types;
  final Map<String, String> groupNames;
  final bool isCoach;
  final ValueChanged<PlannedSession> onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (sessions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.event_available_outlined, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(longDayLabel(day), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Rien de prévu ce jour.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (isCoach) ...[
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une séance'),
              ),
            ),
          ],
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: sessions.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) return Text(longDayLabel(day), style: theme.textTheme.titleMedium);
        final s = sessions[i - 1];
        return SessionCard(
          session: s,
          type: types[s.typeId],
          groupName: groupNames[s.groupId],
          onTap: () => onOpen(s),
        );
      },
    );
  }
}

// --- Tablette : 7 colonnes -----------------------------------------------------------------

class _WeekColumns extends ConsumerWidget {
  const _WeekColumns({
    required this.monday,
    required this.today,
    required this.sessions,
    required this.types,
    required this.groupNames,
    required this.isCoach,
    required this.onOpen,
    required this.onAdd,
  });

  final DateTime monday;
  final DateTime today;
  final List<PlannedSession> sessions;
  final Map<String, SessionType> types;
  final Map<String, String> groupNames;
  final bool isCoach;
  final ValueChanged<PlannedSession> onOpen;
  final ValueChanged<DateTime> onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _DayColumn(
                day: addDays(monday, i),
                isToday: addDays(monday, i) == today,
                sessions: sessions.where((s) => s.date == isoDate(addDays(monday, i))).toList(),
                types: types,
                groupNames: groupNames,
                isCoach: isCoach,
                onOpen: onOpen,
                onAdd: () => onAdd(addDays(monday, i)),
                onDrop: (s) => guarded(
                  context,
                  () => ref.read(sessionActionsProvider).move(s.id, isoDate(addDays(monday, i))),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.isToday,
    required this.sessions,
    required this.types,
    required this.groupNames,
    required this.isCoach,
    required this.onOpen,
    required this.onAdd,
    required this.onDrop,
  });

  final DateTime day;
  final bool isToday;
  final List<PlannedSession> sessions;
  final Map<String, SessionType> types;
  final Map<String, String> groupNames;
  final bool isCoach;
  final ValueChanged<PlannedSession> onOpen;
  final VoidCallback onAdd;
  final ValueChanged<PlannedSession> onDrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iso = isoDate(day);

    Widget card(PlannedSession s) {
      final child = SessionCard(
        session: s,
        type: types[s.typeId],
        groupName: groupNames[s.groupId],
        compact: true,
        onTap: () => onOpen(s),
      );
      if (!isCoach) return child;
      return LongPressDraggable<PlannedSession>(
        key: Key('drag-${s.id}'),
        data: s,
        feedback: Material(
          color: Colors.transparent,
          elevation: 6,
          child: SizedBox(
            width: 150,
            child: SessionCard(session: s, type: types[s.typeId], groupName: groupNames[s.groupId], compact: true),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: child),
        child: child,
      );
    }

    return DragTarget<PlannedSession>(
      onWillAcceptWithDetails: (d) => isCoach && d.data.date != iso,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          key: Key('day-$iso'),
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: hovering ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
            border: hovering ? Border.all(color: theme.colorScheme.primary, width: 2) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Text(
                      weekdayLetter(day),
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday ? theme.colorScheme.primary : null,
                      ),
                      child: Text(
                        '${day.day}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: isToday ? theme.colorScheme.onPrimary : null,
                          fontWeight: isToday ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                    if (isCoach)
                      IconButton(
                        key: Key('add-$iso'),
                        tooltip: 'Ajouter une séance le ${longDayLabel(day)}',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add, size: 20),
                        onPressed: onAdd,
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => card(sessions[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
