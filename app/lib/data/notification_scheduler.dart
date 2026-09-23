import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/notifications.dart';
import 'models.dart';
import 'queries.dart';

/// Titres des séances d'un athlète, groupés par jour (clé `yyyy-MM-dd`), restreints à ses
/// groupes — logique séparée du provider pour rester testable sans le vrai plugin de
/// notifications (indisponible dans les tests de widgets).
Map<String, List<String>> titlesByDateForAthlete(List<PlannedSession> sessions, Set<String> myGroups) {
  final byDate = <String, List<String>>{};
  for (final s in sessions) {
    if (!myGroups.contains(s.groupId)) continue;
    (byDate[s.date] ??= []).add(s.title);
  }
  return byDate;
}

/// Reprogramme les rappels à 8h dès que les séances à venir de l'athlète changent (watché une
/// fois à la racine, comme `syncLifecycleProvider`). Rien pour un coach : c'est un rappel
/// personnel façon Strava, pas une alerte sur tout ce que son club a de prévu.
final notificationSchedulerProvider = Provider<void>((ref) {
  final athlete = ref.watch(myAthleteProvider);
  if (athlete == null) return;

  final groupLinks = ref.watch(groupLinksProvider).value ?? const <String, Set<String>>{};
  final today = dateOnly(DateTime.now());
  final range = '${isoDate(today)}|${isoDate(addDays(today, 6))}';
  final sessions = ref.watch(sessionsForRangeProvider(range)).value ?? const <PlannedSession>[];

  final titlesByDate = titlesByDateForAthlete(sessions, groupLinks[athlete.id] ?? const <String>{});
  requestNotificationPermission().then((_) => scheduleSessionReminders(titlesByDate));
});
