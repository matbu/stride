import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' show Fake, WidgetTester, addTearDown;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:coach/core/theme.dart';
import 'package:coach/data/actions.dart';
import 'package:coach/data/database.dart';
import 'package:coach/data/drafts.dart';
import 'package:coach/data/models.dart';
import 'package:coach/data/queries.dart';
import 'package:coach/data/session_actions.dart';

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

  @override
  Future<void> setGroupMembership({
    required String clubId,
    required Athlete athlete,
    required String groupId,
    required bool member,
  }) async {
    groupToggles.add((groupId, member));
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
}

class FakeClubActions extends Fake implements ClubActions {
  final approved = <String>[];
  @override
  Future<void> approve(String membershipId) async => approved.add(membershipId);
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
}) {
  final m = me ?? membership();
  return [
    userProvider.overrideWithValue(testUser),
    myMembershipsProvider.overrideWith((ref) => Stream.value([m])),
    clubProvider.overrideWith((ref) => Stream.value(const Club(id: 'c1', name: 'AC Test'))),
    groupsProvider.overrideWith((ref) => Stream.value(groups)),
    sessionTypesProvider.overrideWith((ref) => Stream.value(types)),
    sessionsForWeekProvider.overrideWith((ref, monday) => Stream.value(sessions)),
    templatesProvider.overrideWith((ref) => Stream.value(templates)),
    blocksForSessionProvider.overrideWith((ref, id) => Stream.value(blocks[id] ?? const [])),
    membersProvider.overrideWith((ref) => Stream.value([m])),
    pendingRequestsProvider.overrideWith((ref) => Stream.value(requests)),
    athletesProvider.overrideWith((ref) => Stream.value(athletes)),
    groupLinksProvider.overrideWith((ref) => Stream.value(links)),
    planningActionsProvider.overrideWithValue(planning ?? FakePlanning()),
    sessionActionsProvider.overrideWithValue(sessionActions ?? FakeSessions()),
    if (clubActions != null) clubActionsProvider.overrideWithValue(clubActions),
  ];
}
