import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../../data/session_actions.dart';
import '../common.dart';
import 'month_grid.dart';
import 'navigation.dart';
import 'session_card.dart';

/// Largeur à partir de laquelle on affiche les 7 jours côte à côte (tablette, paysage).
const weekColumnsMinWidth = 720.0;

/// Vue semaine, et vue mois (bouton calendrier dans l'AppBar).
///  * Téléphone : bande des 7 jours (pastilles de couleur par type) et agenda du jour
///    sélectionné ; glisser horizontalement change de jour. Un coach déplace une séance
///    vers un autre jour en la maintenant appuyée puis en la glissant sur la pastille du jour,
///    ou la supprime en la glissant vers la gauche (confirmation demandée).
///  * Tablette : 7 colonnes. Mêmes gestes, directement d'une colonne à l'autre.
///  * Vue mois : grille façon Google Calendar, juste des pastilles ; toucher un jour revient
///    à l'agenda de ce jour.
///  * Filtre coach (bande de chips) : Tous, ou un groupe. Chaque chip de groupe a un menu
///    déroulant (« Tous » + les athlètes du groupe) pour n'afficher que le statut « fait / non
///    fait » d'un athlète (lecture seule pour le coach — façon Pronote, seul l'athlète le
///    marque) — pas de liste plate de tous les athlètes du club, invivable pour un gros effectif.
class WeekScreen extends ConsumerStatefulWidget {
  const WeekScreen({super.key});

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  DateTime _selected = dateOnly(DateTime.now());
  String? _groupFilter; // null = tous les groupes
  String? _athleteFilter; // mutuellement exclusif avec _groupFilter
  bool _monthView = false;
  late DateTime _monthCursor = DateTime(_selected.year, _selected.month, 1);

  DateTime get _monday => mondayOf(_selected);

  void _shiftDays(int n) => setState(() => _selected = addDays(_selected, n));

  void _shiftMonths(int n) => setState(() => _monthCursor = DateTime(_monthCursor.year, _monthCursor.month + n, 1));

  void _toggleMonthView() => setState(() {
        _monthView = !_monthView;
        if (_monthView) _monthCursor = DateTime(_selected.year, _selected.month, 1);
      });

  void _setGroupFilter(String? id) => setState(() {
        _groupFilter = id;
        _athleteFilter = null;
      });

  /// Choisi depuis le menu déroulant d'un chip de groupe : `athleteId` null = « Tous » (rien
  /// à filtrer de plus que le groupe). Un athlète ne réduit pas la liste des séances (déjà
  /// celles du groupe) : il choisit de qui on affiche le statut fait / non fait.
  void _setGroupAthleteFilter(String groupId, String? athleteId) => setState(() {
        _groupFilter = groupId;
        _athleteFilter = athleteId;
      });

  @override
  Widget build(BuildContext context) {
    final isCoach = ref.watch(isCoachProvider);
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final athletes = ref.watch(athletesProvider).value ?? const <Athlete>[];
    final groupLinks = ref.watch(groupLinksProvider).value ?? const <String, Set<String>>{};
    final types = {for (final t in ref.watch(sessionTypesProvider).value ?? const <SessionType>[]) t.id: t};
    final groupNames = {for (final g in groups) g.id: g.name};
    final all = ref.watch(sessionsForWeekProvider(isoDate(_monday))).value ?? const <PlannedSession>[];
    final sessions = _groupFilter == null ? all : all.where((s) => s.groupId == _groupFilter).toList();
    final today = dateOnly(DateTime.now());

    // Le suivi « fait / non fait » : le sien pour un athlète, celui de l'athlète filtré pour un
    // coach (lecture seule — un coach ne marque jamais à la place de l'athlète).
    final myAthlete = ref.watch(myAthleteProvider);
    final statusAthleteId = isCoach ? _athleteFilter : myAthlete?.id;
    final doneIds = statusAthleteId == null
        ? const <String>{}
        : ref.watch(completionsForAthleteProvider(statusAthleteId)).value ?? const <String>{};
    final canToggleDone = !isCoach && myAthlete != null;

    void toggleDone(PlannedSession s) {
      final clubId = ref.read(clubIdProvider);
      if (clubId == null || statusAthleteId == null) return;
      guarded(
        context,
        () => doneIds.contains(s.id)
            ? ref.read(sessionActionsProvider).markNotDone(s.id, statusAthleteId)
            : ref.read(sessionActionsProvider).markDone(s.id, statusAthleteId, clubId: clubId),
      );
    }

    void open(PlannedSession s) => openSession(
          context,
          s,
          isCoach: isCoach,
          type: types[s.typeId],
          groupName: groupNames[s.groupId],
        );

    void moveToDay(PlannedSession s, DateTime day) {
      final iso = isoDate(day);
      if (s.date == iso) return;
      guarded(context, () => ref.read(sessionActionsProvider).move(s.id, iso));
    }

    void deleteSession(PlannedSession s) =>
        guarded(context, () => ref.read(sessionActionsProvider).delete(s.id));

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= weekColumnsMinWidth;
      return Scaffold(
        appBar: AppBar(
          title: Text(_monthView ? monthLabel(_monthCursor) : weekRangeLabel(_monday)),
          actions: [
            if (_monthView
                ? (_monthCursor.year != today.year || _monthCursor.month != today.month)
                : _selected != today)
              TextButton(
                onPressed: () => setState(() {
                  if (_monthView) {
                    _monthCursor = DateTime(today.year, today.month, 1);
                  } else {
                    _selected = today;
                  }
                }),
                child: const Text('Aujourd’hui'),
              ),
            IconButton(
              tooltip: _monthView ? 'Mois précédent' : 'Semaine précédente',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _monthView ? _shiftMonths(-1) : _shiftDays(-7),
            ),
            IconButton(
              tooltip: _monthView ? 'Mois suivant' : 'Semaine suivante',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _monthView ? _shiftMonths(1) : _shiftDays(7),
            ),
            IconButton(
              key: const Key('toggle-month-view'),
              tooltip: _monthView ? 'Vue semaine' : 'Vue mois',
              icon: Icon(_monthView ? Icons.view_week_outlined : Icons.calendar_view_month_outlined),
              onPressed: _toggleMonthView,
            ),
          ],
        ),
        floatingActionButton: isCoach
            ? FloatingActionButton.extended(
                key: const Key('add-session'),
                heroTag: 'week-add-session',
                onPressed: () => startNewSession(context, date: _selected, groupId: _groupFilter),
                icon: const Icon(Icons.add),
                label: const Text('Séance'),
              )
            : null,
        body: Column(
          children: [
            if (!_monthView && !wide)
              _DayStrip(
                monday: _monday,
                selected: _selected,
                today: today,
                sessions: sessions,
                types: types,
                isCoach: isCoach,
                onSelect: (d) => setState(() => _selected = d),
                onDrop: moveToDay,
              ),
            if (isCoach && groups.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _FilterChip(
                      label: 'Tous',
                      selected: _groupFilter == null && _athleteFilter == null,
                      onTap: () => setState(() {
                        _groupFilter = null;
                        _athleteFilter = null;
                      }),
                    ),
                    for (final g in groups)
                      _GroupFilterChip(
                        key: Key('filter-group-${g.name}'),
                        groupName: g.name,
                        label: _groupFilter == g.id && _athleteFilter != null
                            ? '${g.name} · ${_athleteName(athletes, _athleteFilter!)}'
                            : g.name,
                        selected: _groupFilter == g.id,
                        athletes: athletes.where((a) => (groupLinks[a.id] ?? const <String>{}).contains(g.id)).toList(),
                        onSelectGroup: () => _setGroupFilter(g.id),
                        onSelectAthlete: (athleteId) => _setGroupAthleteFilter(g.id, athleteId),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: _monthView
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: MonthGrid(
                        month: _monthCursor,
                        today: today,
                        types: types,
                        groupFilter: _groupFilter,
                        onSelectDay: (d) => setState(() {
                          _selected = d;
                          _monthView = false;
                        }),
                      ),
                    )
                  : wide
                      ? _WeekColumns(
                          monday: _monday,
                          today: today,
                          sessions: sessions,
                          types: types,
                          groupNames: groupNames,
                          isCoach: isCoach,
                          onOpen: open,
                          onAdd: (d) => startNewSession(context, date: d, groupId: _groupFilter),
                          onDelete: deleteSession,
                          doneIds: statusAthleteId == null ? null : doneIds,
                          onToggleDone: canToggleDone ? toggleDone : null,
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
                            onDelete: deleteSession,
                            doneIds: statusAthleteId == null ? null : doneIds,
                            onToggleDone: canToggleDone ? toggleDone : null,
                          ),
                        ),
            ),
          ],
        ),
      );
    });
  }
}

/// Confirmation avant suppression depuis la vue semaine (glisser une carte vers la gauche).
Future<bool> _confirmDeleteSession(BuildContext context, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Supprimer la séance ?'),
      content: Text('« $title » sera supprimée pour tout le monde.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
      ],
    ),
  );
  return ok == true;
}

Widget _deleteBackground(ThemeData theme) => Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      margin: const EdgeInsets.symmetric(vertical: 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
    );

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );
}

String _athleteName(List<Athlete> athletes, String id) {
  for (final a in athletes) {
    if (a.id == id) return a.fullName;
  }
  return '';
}

/// Chip de groupe avec un menu déroulant pour restreindre à un athlète de ce groupe (son statut
/// fait / non fait) sans lister tous les athlètes du club au même niveau — invivable à 150.
class _GroupFilterChip extends StatelessWidget {
  const _GroupFilterChip({
    super.key,
    required this.groupName,
    required this.label,
    required this.selected,
    required this.athletes,
    required this.onSelectGroup,
    required this.onSelectAthlete,
  });

  /// Nom du groupe : stable, sert de clé (contrairement à `label`, qui varie avec l'athlète choisi).
  final String groupName;
  final String label;
  final bool selected;
  final List<Athlete> athletes;
  final VoidCallback onSelectGroup;
  final ValueChanged<String?> onSelectAthlete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? theme.colorScheme.onSecondaryContainer : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Material(
        color: selected ? theme.colorScheme.secondaryContainer : theme.colorScheme.surfaceContainerHighest,
        shape: const StadiumBorder(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              customBorder: const StadiumBorder(),
              onTap: onSelectGroup,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 8, athletes.isEmpty ? 12 : 2, 8),
                child: Text(label, style: theme.textTheme.labelLarge?.copyWith(color: fg)),
              ),
            ),
            if (athletes.isNotEmpty)
              PopupMenuButton<String?>(
                key: Key('filter-athlete-menu-$groupName'),
                tooltip: 'Filtrer par athlète',
                onSelected: onSelectAthlete,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: null, child: Text('Tous')),
                  for (final a in athletes) PopupMenuItem(value: a.id, child: Text(a.fullName)),
                ],
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
                  child: Icon(Icons.arrow_drop_down, color: fg),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Téléphone -----------------------------------------------------------------------------

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.monday,
    required this.selected,
    required this.today,
    required this.sessions,
    required this.types,
    required this.isCoach,
    required this.onSelect,
    required this.onDrop,
  });

  final DateTime monday;
  final DateTime selected;
  final DateTime today;
  final List<PlannedSession> sessions;
  final Map<String, SessionType> types;
  final bool isCoach;
  final ValueChanged<DateTime> onSelect;
  final void Function(PlannedSession session, DateTime day) onDrop;

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
    final iso = isoDate(day);
    final colors = <Color>{
      for (final s in sessions)
        if (s.date == iso) (types[s.typeId]?.color ?? theme.colorScheme.outline),
    }.take(4).toList();

    return DragTarget<PlannedSession>(
      onWillAcceptWithDetails: (d) => isCoach && d.data.date != iso,
      onAcceptWithDetails: (d) => onDrop(d.data, day),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Semantics(
          selected: isSelected,
          label: longDayLabel(day),
          child: InkWell(
            key: Key('day-strip-$iso'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelect(day),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: hovering ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
                border: hovering ? Border.all(color: theme.colorScheme.primary, width: 2) : null,
              ),
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
                      border:
                          (isToday && !isSelected) ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
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
      },
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
    required this.onDelete,
    this.doneIds,
    this.onToggleDone,
  });

  final DateTime day;
  final List<PlannedSession> sessions;
  final Map<String, SessionType> types;
  final Map<String, String> groupNames;
  final bool isCoach;
  final ValueChanged<PlannedSession> onOpen;
  final VoidCallback onAdd;
  final ValueChanged<PlannedSession> onDelete;

  /// Null : pas de contexte athlète, aucun indicateur affiché.
  final Set<String>? doneIds;
  final ValueChanged<PlannedSession>? onToggleDone;

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
        return _card(context, sessions[i - 1]);
      },
    );
  }

  Widget _card(BuildContext context, PlannedSession s) {
    final child = SessionCard(
      session: s,
      type: types[s.typeId],
      groupName: groupNames[s.groupId],
      onTap: () => onOpen(s),
      done: doneIds?.contains(s.id),
      onToggleDone: onToggleDone == null ? null : () => onToggleDone!(s),
    );
    if (!isCoach) return child;
    final draggable = LongPressDraggable<PlannedSession>(
      key: Key('drag-${s.id}'),
      data: s,
      feedback: Material(
        color: Colors.transparent,
        elevation: 6,
        child: SizedBox(
          width: 260,
          child: SessionCard(session: s, type: types[s.typeId], groupName: groupNames[s.groupId], compact: true),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
    return Dismissible(
      key: Key('dismiss-${s.id}'),
      direction: DismissDirection.endToStart,
      background: _deleteBackground(Theme.of(context)),
      confirmDismiss: (_) => _confirmDeleteSession(context, s.title),
      onDismissed: (_) => onDelete(s),
      child: draggable,
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
    required this.onDelete,
    this.doneIds,
    this.onToggleDone,
  });

  final DateTime monday;
  final DateTime today;
  final List<PlannedSession> sessions;
  final Map<String, SessionType> types;
  final Map<String, String> groupNames;
  final bool isCoach;
  final ValueChanged<PlannedSession> onOpen;
  final ValueChanged<DateTime> onAdd;
  final ValueChanged<PlannedSession> onDelete;
  final Set<String>? doneIds;
  final ValueChanged<PlannedSession>? onToggleDone;

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
                onDelete: onDelete,
                doneIds: doneIds,
                onToggleDone: onToggleDone,
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
    required this.onDelete,
    this.doneIds,
    this.onToggleDone,
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
  final ValueChanged<PlannedSession> onDelete;
  final Set<String>? doneIds;
  final ValueChanged<PlannedSession>? onToggleDone;

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
        done: doneIds?.contains(s.id),
        onToggleDone: onToggleDone == null ? null : () => onToggleDone!(s),
      );
      if (!isCoach) return child;
      final draggable = LongPressDraggable<PlannedSession>(
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
      return Dismissible(
        key: Key('dismiss-${s.id}'),
        direction: DismissDirection.endToStart,
        background: _deleteBackground(theme),
        confirmDismiss: (_) => _confirmDeleteSession(context, s.title),
        onDismissed: (_) => onDelete(s),
        child: draggable,
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
