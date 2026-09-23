import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/queries.dart';

/// Vue mois façon Google Calendar : une grille des semaines complètes couvrant le mois
/// (déborde donc un peu sur les mois voisins). Chaque jour montre juste des pastilles de
/// couleur par type, comme la bande des 7 jours ; toucher un jour le sélectionne (c'est
/// l'écran appelant qui décide quoi en faire, typiquement revenir à l'agenda de ce jour-là).
class MonthGrid extends ConsumerWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.today,
    required this.types,
    this.groupFilter,
    this.athleteFilter,
    this.groupLinks = const {},
    required this.onSelectDay,
  });

  /// N'importe quel jour du mois à afficher (seul le mois/année compte).
  final DateTime month;
  final DateTime today;
  final Map<String, SessionType> types;
  final String? groupFilter;
  final String? athleteFilter;
  final Map<String, Set<String>> groupLinks;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final lastOfMonth = DateTime(month.year, month.month + 1, 0);
    final gridStart = mondayOf(firstOfMonth);
    final gridEnd = addDays(mondayOf(lastOfMonth), 6);
    final weeks = (gridEnd.difference(gridStart).inDays + 1) ~/ 7;

    final range = '${isoDate(gridStart)}|${isoDate(gridEnd)}';
    final all = ref.watch(sessionsForRangeProvider(range)).value ?? const <PlannedSession>[];
    final sessions = groupFilter != null
        ? all.where((s) => s.groupId == groupFilter).toList()
        : athleteFilter != null
            ? all.where((s) => (groupLinks[athleteFilter] ?? const <String>{}).contains(s.groupId)).toList()
            : all;
    final byDay = <String, List<PlannedSession>>{};
    for (final s in sessions) {
      (byDay[s.date] ??= []).add(s);
    }

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    weekdayLetter(addDays(gridStart, i)),
                    style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Column(
            children: [
              for (var w = 0; w < weeks; w++)
                Expanded(
                  child: Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(child: _dayCell(context, theme, addDays(gridStart, w * 7 + i), byDay)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayCell(BuildContext context, ThemeData theme, DateTime day, Map<String, List<PlannedSession>> byDay) {
    final iso = isoDate(day);
    final inMonth = day.month == month.month;
    final isToday = day == today;
    final colors = <Color>{
      for (final s in byDay[iso] ?? const <PlannedSession>[])
        (types[s.typeId]?.color ?? theme.colorScheme.outline),
    }.take(4).toList();

    return InkWell(
      key: Key('month-day-$iso'),
      onTap: () => onSelectDay(day),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday ? theme.colorScheme.primary : null,
              ),
              child: Text(
                '${day.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isToday
                      ? theme.colorScheme.onPrimary
                      : (inMonth ? null : theme.colorScheme.outline),
                  fontWeight: isToday ? FontWeight.w700 : null,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final c in colors)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
