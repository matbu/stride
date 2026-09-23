import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import 'database.dart';
import 'models.dart';

/// Requête SQLite réactive : le flux ré-émet à chaque changement des tables lues, que la
/// modification vienne de l'utilisateur ou de la synchronisation.
Stream<List<T>> _query<T>(
  Ref ref,
  String sql,
  List<Object?> params,
  T Function(DbRow) map,
) {
  final db = ref.watch(powerSyncProvider);
  return db.watch(sql, parameters: params).map((rows) => [for (final r in rows) map(r)]);
}

// --- Compte et club ---------------------------------------------------------------------

final myMembershipsProvider = StreamProvider<List<Membership>>((ref) {
  final uid = ref.watch(userProvider)?.id;
  if (uid == null) return Stream.value(const []);
  return _query(ref, 'SELECT * FROM memberships WHERE user_id = ?', [uid], Membership.fromRow);
});

final activeMembershipProvider = Provider<Membership?>((ref) {
  final list = ref.watch(myMembershipsProvider).value ?? const [];
  return list.where((m) => m.isActive).firstOrNull;
});

final pendingMembershipProvider = Provider<Membership?>((ref) {
  final list = ref.watch(myMembershipsProvider).value ?? const [];
  return list.where((m) => !m.isActive).firstOrNull;
});

final clubIdProvider = Provider<String?>((ref) => ref.watch(activeMembershipProvider)?.clubId);

final isCoachProvider = Provider<bool>(
  (ref) => ref.watch(activeMembershipProvider)?.role.isCoach ?? false,
);

final clubProvider = StreamProvider<Club?>((ref) {
  final clubId = ref.watch(clubIdProvider);
  if (clubId == null) return Stream.value(null);
  return _query(ref, 'SELECT * FROM clubs WHERE id = ?', [clubId], Club.fromRow)
      .map((l) => l.firstOrNull);
});

/// Profil libre-service du club (description, logo) — visible de tout membre, modifiable par
/// un coach (voir `ClubProfileActions`).
final clubProfileProvider = StreamProvider<ClubProfile?>((ref) {
  final clubId = ref.watch(clubIdProvider);
  if (clubId == null) return Stream.value(null);
  return _query(ref, 'SELECT * FROM club_profiles WHERE id = ?', [clubId], ClubProfile.fromRow)
      .map((l) => l.firstOrNull);
});

// --- Référentiels du club -----------------------------------------------------------------

final groupsProvider = StreamProvider<List<Group>>((ref) {
  final clubId = ref.watch(clubIdProvider);
  if (clubId == null) return Stream.value(const []);
  return _query(
    ref,
    'SELECT * FROM training_groups WHERE club_id = ? AND archived = 0 ORDER BY sort_order, name',
    [clubId],
    Group.fromRow,
  );
});

final sessionTypesProvider = StreamProvider<List<SessionType>>((ref) {
  final clubId = ref.watch(clubIdProvider);
  if (clubId == null) return Stream.value(const []);
  return _query(
    ref,
    'SELECT * FROM session_types WHERE club_id = ? AND archived = 0 ORDER BY sort_order',
    [clubId],
    SessionType.fromRow,
  );
});

final membersProvider = StreamProvider<List<Membership>>((ref) {
  final clubId = ref.watch(clubIdProvider);
  if (clubId == null) return Stream.value(const []);
  return _query(
    ref,
    "SELECT * FROM memberships WHERE club_id = ? AND status = 'active' ORDER BY display_name",
    [clubId],
    Membership.fromRow,
  );
});

/// Demandes d'adhésion en attente (synchronisées uniquement pour les coachs).
final pendingRequestsProvider = StreamProvider<List<Membership>>((ref) {
  final clubId = ref.watch(clubIdProvider);
  if (clubId == null) return Stream.value(const []);
  return _query(
    ref,
    "SELECT * FROM memberships WHERE club_id = ? AND status = 'pending' ORDER BY display_name",
    [clubId],
    Membership.fromRow,
  );
});

final athletesProvider = StreamProvider<List<Athlete>>((ref) {
  final clubId = ref.watch(clubIdProvider);
  if (clubId == null) return Stream.value(const []);
  return _query(
    ref,
    'SELECT * FROM athletes WHERE club_id = ? ORDER BY full_name',
    [clubId],
    Athlete.fromRow,
  );
});

/// Ma fiche athlète dans le club courant (null pour un coach).
final myAthleteProvider = Provider<Athlete?>((ref) {
  final uid = ref.watch(userProvider)?.id;
  final athletes = ref.watch(athletesProvider).value ?? const [];
  return athletes.where((a) => a.userId == uid).firstOrNull;
});

/// Profil (photo, bio, lien FFA) d'un athlète — soit le sien, soit celui consulté par un coach.
final athleteProfileProvider = StreamProvider.family<AthleteProfile?, String>((ref, athleteId) {
  return _query(
    ref,
    'SELECT * FROM athlete_profiles WHERE id = ?',
    [athleteId],
    AthleteProfile.fromRow,
  ).map((l) => l.firstOrNull);
});

/// Records personnels d'un athlète, les plus récents d'abord.
final athleteRecordsProvider = StreamProvider.family<List<AthleteRecord>, String>((ref, athleteId) {
  return _query(
    ref,
    'SELECT * FROM athlete_records WHERE athlete_id = ? '
    'ORDER BY achieved_on IS NULL, achieved_on DESC, discipline',
    [athleteId],
    AthleteRecord.fromRow,
  );
});

/// Séances qu'un athlète a marquées faites (l'ensemble de leurs `session_id`).
final completionsForAthleteProvider = StreamProvider.family<Set<String>, String>((ref, athleteId) {
  return _query(
    ref,
    'SELECT session_id FROM session_completions WHERE athlete_id = ?',
    [athleteId],
    (r) => r['session_id'] as String,
  ).map((rows) => rows.toSet());
});

/// group_id → ensemble des athlètes présents ce jour-là (existence de ligne = présent).
final attendanceForDateProvider = StreamProvider.family<Map<String, Set<String>>, String>((ref, date) {
  return _query(
    ref,
    'SELECT group_id, athlete_id FROM attendances WHERE date = ?',
    [date],
    (r) => (r['group_id'] as String, r['athlete_id'] as String),
  ).map((rows) {
    final map = <String, Set<String>>{};
    for (final (groupId, athleteId) in rows) {
      (map[groupId] ??= {}).add(athleteId);
    }
    return map;
  });
});

/// Dates de présence d'un athlète, les plus récentes d'abord (historique consulté par un coach).
final attendanceDatesForAthleteProvider = StreamProvider.family<List<String>, String>((ref, athleteId) {
  return _query(
    ref,
    'SELECT date FROM attendances WHERE athlete_id = ? ORDER BY date DESC',
    [athleteId],
    (r) => r['date'] as String,
  );
});

/// athlete_id → ensemble des groupes. Un coach reçoit tous les liens du club, un athlète
/// uniquement les siens (règles de sync).
final groupLinksProvider = StreamProvider<Map<String, Set<String>>>((ref) {
  final clubId = ref.watch(clubIdProvider);
  if (clubId == null) return Stream.value(const {});
  return _query(
    ref,
    'SELECT athlete_id, group_id FROM group_athletes WHERE club_id = ?',
    [clubId],
    (r) => (r['athlete_id'] as String, r['group_id'] as String),
  ).map((links) {
    final map = <String, Set<String>>{};
    for (final (athleteId, groupId) in links) {
      (map[athleteId] ??= {}).add(groupId);
    }
    return map;
  });
});

// --- Séances ----------------------------------------------------------------------------

/// Séances placées d'une semaine ; la clé est le lundi au format `yyyy-MM-dd`.
final sessionsForWeekProvider =
    StreamProvider.family<List<PlannedSession>, String>((ref, mondayIso) {
  final clubId = ref.watch(clubIdProvider);
  if (clubId == null) return Stream.value(const []);
  final sunday = isoDate(addDays(parseIsoDate(mondayIso), 6));
  return _query(
    ref,
    'SELECT * FROM sessions WHERE club_id = ? AND is_template = 0 '
    'AND scheduled_date BETWEEN ? AND ? '
    'ORDER BY scheduled_date, start_time IS NULL, start_time, title',
    [clubId, mondayIso, sunday],
    PlannedSession.fromRow,
  );
});

/// Séances placées entre deux jours (inclus) ; la clé est `débutIso|finIso` (vue mois : la
/// grille déborde sur les semaines des mois voisins, d'où un intervalle plutôt qu'un mois pile).
final sessionsForRangeProvider =
    StreamProvider.family<List<PlannedSession>, String>((ref, range) {
  final clubId = ref.watch(clubIdProvider);
  if (clubId == null) return Stream.value(const []);
  final parts = range.split('|');
  return _query(
    ref,
    'SELECT * FROM sessions WHERE club_id = ? AND is_template = 0 '
    'AND scheduled_date BETWEEN ? AND ? '
    'ORDER BY scheduled_date, start_time IS NULL, start_time, title',
    [clubId, parts[0], parts[1]],
    PlannedSession.fromRow,
  );
});

/// Séances sœurs d'un lot multi-groupes (même `linked_id`), pour préremplir leurs groupes à
/// l'édition (voir `SessionEditorScreen`). Vide pour une séance à un seul groupe.
final linkedSessionsProvider = StreamProvider.family<List<PlannedSession>, String>((ref, linkedId) {
  return _query(
    ref,
    'SELECT * FROM sessions WHERE linked_id = ?',
    [linkedId],
    PlannedSession.fromRow,
  );
});

/// Modèles de la bibliothèque du club.
final templatesProvider = StreamProvider<List<Template>>((ref) {
  final clubId = ref.watch(clubIdProvider);
  if (clubId == null) return Stream.value(const []);
  return _query(
    ref,
    'SELECT * FROM sessions WHERE club_id = ? AND is_template = 1 ORDER BY title COLLATE NOCASE',
    [clubId],
    Template.fromRow,
  );
});

/// Blocs d'une séance ou d'un modèle, dans l'ordre.
final blocksForSessionProvider =
    StreamProvider.family<List<SessionBlock>, String>((ref, sessionId) {
  return _query(
    ref,
    'SELECT * FROM session_blocks WHERE session_id = ? ORDER BY position',
    [sessionId],
    SessionBlock.fromRow,
  );
});
