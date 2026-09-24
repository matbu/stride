import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' show Fake, WidgetTester, addTearDown;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trackclub/core/theme.dart';
import 'package:trackclub/data/actions.dart';
import 'package:trackclub/data/club_profile_actions.dart';
import 'package:trackclub/data/database.dart';
import 'package:trackclub/data/drafts.dart';
import 'package:trackclub/data/event_actions.dart';
import 'package:trackclub/data/models.dart';
import 'package:trackclub/data/profile_actions.dart';
import 'package:trackclub/data/queries.dart';
import 'package:trackclub/data/session_actions.dart';

const testUser = User(
  id: 'u-julie',
  appMetadata: {},
  userMetadata: {'display_name': 'Julie Tournier'},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

Membership membership({
  String id = 'm1',
  String clubId = 'c1',
  String userId = 'u-julie',
  ClubRole role = ClubRole.owner,
  bool active = true,
  String name = 'Julie Tournier',
}) =>
    Membership(id: id, clubId: clubId, userId: userId, role: role, isActive: active, displayName: name);

const fractionne = SessionType(id: 't-frac', name: 'Fractionné', color: Color(0xFFE5484D), icon: 'bolt');
const endurance = SessionType(id: 't-endu', name: 'Endurance', color: Color(0xFF2E9E5B), icon: 'run');
const sprintGroup = Group(id: 'g-sprint', name: 'Sprint');
const demiGroup = Group(id: 'g-demi', name: 'Demi-fond');

/// Taille de téléphone : la vue semaine affiche alors un jour à la fois (sinon 800 px → 7 colonnes).
void phoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Enveloppe un écran dans une app Material française avec les surcharges de providers.
Widget testApp(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    );

// --- Faux accès aux données ---------------------------------------------------------------

/// Faux accès en écriture (groupes, athlètes) : enregistre les appels au lieu de toucher une base.
class FakePlanning extends Fake implements PlanningActions {
  final groupToggles = <(String, bool)>[];
  final attendanceToggles = <(String groupId, String athleteId, bool present)>[];

  @override
  Future<void> setGroupMembership({
    required String clubId,
    required Athlete athlete,
    required String groupId,
    required bool member,
  }) async {
    groupToggles.add((groupId, member));
  }

  @override
  Future<void> setAttendance({
    required String clubId,
    required String groupId,
    required String athleteId,
    required String date,
    required bool present,
  }) async {
    attendanceToggles.add((groupId, athleteId, present));
  }
}

/// Faux accès aux séances : garde une trace de chaque écriture demandée.
class FakeSessions extends Fake implements SessionActions {
  final saved = <SessionDraft>[];
  final placed = <({String templateId, Set<String> groups, String date, String? time})>[];
  final moved = <(String, String)>[];
  final deleted = <String>[];

  @override
  Future<void> save(SessionDraft d, {required String clubId}) async => saved.add(d);

  @override
  Future<void> place({
    required String templateId,
    required String clubId,
    required Set<String> groupIds,
    required String date,
    String? startTime,
  }) async {
    placed.add((templateId: templateId, groups: {...groupIds}, date: date, time: startTime));
  }

  @override
  Future<void> move(String sessionId, String isoDate) async => moved.add((sessionId, isoDate));

  @override
  Future<void> delete(String sessionId) async => deleted.add(sessionId);

  final markedDone = <(String, String)>[];
  final markedNotDone = <(String, String)>[];

  @override
  Future<void> markDone(String sessionId, String athleteId, {required String clubId}) async =>
      markedDone.add((sessionId, athleteId));

  @override
  Future<void> markNotDone(String sessionId, String athleteId) async => markedNotDone.add((sessionId, athleteId));
}

class FakeClubActions extends Fake implements ClubActions {
  final approved = <String>[];
  List<Club> searchResults = const [];
  final searchedQueries = <String>[];
  final joinRequests = <(String, ClubRole)>[];

  @override
  Future<void> approve(String membershipId) async => approved.add(membershipId);

  @override
  Future<List<Club>> searchClubs(String query) async {
    searchedQueries.add(query);
    return searchResults;
  }

  @override
  Future<void> requestJoin(String clubId, ClubRole role) async => joinRequests.add((clubId, role));
}

class FakeEventActions extends Fake implements EventActions {
  final saved = <({String? id, String clubId, EventKind kind, String title, String startDate, String endDate, Set<String> groupIds})>[];
  final deleted = <String>[];

  @override
  Future<void> save({
    String? id,
    required String clubId,
    required EventKind kind,
    required String title,
    required String startDate,
    required String endDate,
    String location = '',
    EventPriority? priority,
    String notes = '',
    required Set<String> groupIds,
  }) async {
    saved.add((id: id, clubId: clubId, kind: kind, title: title.trim(), startDate: startDate, endDate: endDate, groupIds: groupIds));
  }

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

class FakeAccountActions extends Fake implements AccountActions {
  bool deleted = false;
  bool pendingUploads = false;

  @override
  Future<bool> hasPendingUploads() async => pendingUploads;

  @override
  Future<void> deleteAccount() async => deleted = true;
}

class FakeProfileActions extends Fake implements ProfileActions {
  final savedProfiles = <(String athleteId, String bio, String? ffaUrl)>[];
  final savedRecords = <AthleteRecord>[];
  final deletedRecords = <String>[];

  @override
  Future<void> saveProfile({
    required String athleteId,
    required String clubId,
    String? bio,
    String? ffaUrl,
  }) async {
    final url = ffaUrl?.trim();
    savedProfiles.add((athleteId, bio?.trim() ?? '', (url == null || url.isEmpty) ? null : url));
  }

  @override
  Future<void> saveRecord({
    String? id,
    required String athleteId,
    required String clubId,
    required String discipline,
    required String performance,
    String? achievedOn,
    String? competition,
  }) async {
    savedRecords.add(AthleteRecord(
      id: id ?? 'r${savedRecords.length + 1}',
      athleteId: athleteId,
      discipline: discipline.trim(),
      performance: performance.trim(),
      achievedOn: achievedOn,
      competition: competition?.trim() ?? '',
    ));
  }

  @override
  Future<void> deleteRecord(String id) async => deletedRecords.add(id);

  @override
  String avatarUrl(String path) => 'https://example.test/$path';
}

class FakeClubProfileActions extends Fake implements ClubProfileActions {
  final savedDescriptions = <String>[];
  final uploadedLogos = <String>[]; // club ids

  @override
  Future<void> saveDescription({required String clubId, required String description}) async {
    savedDescriptions.add(description.trim());
  }

  @override
  Future<void> uploadLogo({required String clubId, required Uint8List bytes, required String ext}) async {
    uploadedLogos.add(clubId);
  }

  @override
  String logoUrl(String path) => 'https://example.test/$path';
}

const seuil = SessionType(id: 't-seuil', name: 'Seuil / Tempo', color: Color(0xFFF5A524), icon: 'speed');

List<Override> clubOverrides({
  Membership? me,
  List<PlannedSession> sessions = const [],
  List<Group> groups = const [sprintGroup, demiGroup],
  List<SessionType> types = const [fractionne, endurance],
  List<Template> templates = const [],
  Map<String, List<SessionBlock>> blocks = const {},
  FakePlanning? planning,
  FakeSessions? sessionActions,
  List<Membership> requests = const [],
  List<Athlete> athletes = const [],
  Map<String, Set<String>> links = const {},
  FakeClubActions? clubActions,
  Map<String, AthleteProfile> athleteProfiles = const {},
  Map<String, List<AthleteRecord>> athleteRecords = const {},
  FakeProfileActions? profileActions,
  Map<String, Set<String>> completions = const {}, // athleteId -> session_id faits
  Map<String, Set<String>> attendanceToday = const {}, // groupId -> athlete_id présents
  Map<String, List<String>> attendanceDates = const {}, // athleteId -> dates de présence
  ClubProfile? clubProfile,
  FakeClubProfileActions? clubProfileActions,
  FakeAccountActions? accountActions,
  List<Event> events = const [],
  Map<String, Set<String>> eventGroups = const {}, // eventId -> groupIds (vide = tout le club)
  FakeEventActions? eventActions,
}) {
  final m = me ?? membership();
  return [
    userProvider.overrideWithValue(testUser),
    myMembershipsProvider.overrideWith((ref) => Stream.value([m])),
    clubProvider.overrideWith((ref) => Stream.value(const Club(id: 'c1', name: 'AC Test'))),
    clubProfileProvider.overrideWith((ref) => Stream.value(clubProfile)),
    clubProfileActionsProvider.overrideWithValue(clubProfileActions ?? FakeClubProfileActions()),
    accountActionsProvider.overrideWithValue(accountActions ?? FakeAccountActions()),
    eventsForClubProvider.overrideWith((ref) => Stream.value(events)),
    eventGroupsProvider.overrideWith((ref) => Stream.value(eventGroups)),
    eventActionsProvider.overrideWithValue(eventActions ?? FakeEventActions()),
    groupsProvider.overrideWith((ref) => Stream.value(groups)),
    sessionTypesProvider.overrideWith((ref) => Stream.value(types)),
    sessionsForWeekProvider.overrideWith((ref, monday) => Stream.value(sessions)),
    sessionsForRangeProvider.overrideWith((ref, range) => Stream.value(sessions)),
    templatesProvider.overrideWith((ref) => Stream.value(templates)),
    blocksForSessionProvider.overrideWith((ref, id) => Stream.value(blocks[id] ?? const [])),
    membersProvider.overrideWith((ref) => Stream.value([m])),
    pendingRequestsProvider.overrideWith((ref) => Stream.value(requests)),
    athletesProvider.overrideWith((ref) => Stream.value(athletes)),
    groupLinksProvider.overrideWith((ref) => Stream.value(links)),
    planningActionsProvider.overrideWithValue(planning ?? FakePlanning()),
    sessionActionsProvider.overrideWithValue(sessionActions ?? FakeSessions()),
    if (clubActions != null) clubActionsProvider.overrideWithValue(clubActions),
    athleteProfileProvider.overrideWith((ref, id) => Stream.value(athleteProfiles[id])),
    athleteRecordsProvider.overrideWith((ref, id) => Stream.value(athleteRecords[id] ?? const [])),
    profileActionsProvider.overrideWithValue(profileActions ?? FakeProfileActions()),
    completionsForAthleteProvider.overrideWith((ref, id) => Stream.value(completions[id] ?? const <String>{})),
    attendanceForDateProvider.overrideWith((ref, date) => Stream.value(attendanceToday)),
    attendanceDatesForAthleteProvider.overrideWith((ref, id) => Stream.value(attendanceDates[id] ?? const <String>[])),
  ];
}
