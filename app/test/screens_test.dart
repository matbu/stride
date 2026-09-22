import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:trackclub/core/format.dart';
import 'package:trackclub/data/database.dart';
import 'package:trackclub/data/models.dart';
import 'package:trackclub/features/auth/auth_screen.dart';
import 'package:trackclub/features/club/club_screen.dart';
import 'package:trackclub/features/club/profile_screen.dart';
import 'package:trackclub/features/onboarding/join_club_screen.dart';
import 'package:trackclub/features/onboarding/onboarding_screen.dart';
import 'package:trackclub/features/planning/week_screen.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  final today = isoDate(dateOnly(DateTime.now()));

  group('vue semaine', () {
    testWidgets('affiche les séances du jour avec type, titre et groupe', (tester) async {
      phoneScreen(tester);
      final sessions = [
        PlannedSession(
          id: 's1', typeId: fractionne.id, title: '6 × 400 m', groupId: sprintGroup.id,
          date: today, startTime: '18:30:00', durationMin: 90,
        ),
        PlannedSession(id: 's2', typeId: endurance.id, title: 'Footing 45’', groupId: demiGroup.id, date: today),
      ];
      await tester.pumpWidget(testApp(const WeekScreen(), overrides: clubOverrides(sessions: sessions)));
      await tester.pumpAndSettle();

      expect(find.text('6 × 400 m'), findsOneWidget);
      expect(find.text('Fractionné'), findsOneWidget, reason: 'le type est écrit, pas seulement coloré');
      expect(find.text('Sprint'), findsWidgets);
      expect(find.text('18:30 · 90 min'), findsOneWidget);
      expect(find.text('Footing 45’'), findsOneWidget);
      expect(find.text('Endurance'), findsOneWidget);
    });

    testWidgets('jour vide : message et bouton d’ajout pour un coach', (tester) async {
      phoneScreen(tester);
      await tester.pumpWidget(testApp(const WeekScreen(), overrides: clubOverrides()));
      await tester.pumpAndSettle();
      expect(find.text('Rien de prévu ce jour.'), findsOneWidget);
      expect(find.text('Ajouter une séance'), findsOneWidget);
      expect(find.byKey(const Key('add-session')), findsOneWidget);
    });

    testWidgets('un athlète ne voit aucun bouton de création', (tester) async {
      phoneScreen(tester);
      final overrides = clubOverrides(me: membership(role: ClubRole.athlete));
      await tester.pumpWidget(testApp(const WeekScreen(), overrides: overrides));
      await tester.pumpAndSettle();
      expect(find.text('Rien de prévu ce jour.'), findsOneWidget);
      expect(find.text('Ajouter une séance'), findsNothing);
      expect(find.byKey(const Key('add-session')), findsNothing);
    });

    testWidgets('le filtre par groupe restreint la liste', (tester) async {
      phoneScreen(tester);
      final sessions = [
        PlannedSession(id: 's1', typeId: fractionne.id, title: 'Séance sprint', groupId: sprintGroup.id, date: today),
        PlannedSession(id: 's2', typeId: endurance.id, title: 'Séance demi-fond', groupId: demiGroup.id, date: today),
      ];
      await tester.pumpWidget(testApp(const WeekScreen(), overrides: clubOverrides(sessions: sessions)));
      await tester.pumpAndSettle();
      expect(find.text('Séance sprint'), findsOneWidget);
      expect(find.text('Séance demi-fond'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Sprint'));
      await tester.pumpAndSettle();
      expect(find.text('Séance sprint'), findsOneWidget);
      expect(find.text('Séance demi-fond'), findsNothing);
    });
  });

  group('club', () {
    testWidgets('un coach a un accès direct à la déconnexion dans l’AppBar', (tester) async {
      await tester.pumpWidget(testApp(const ClubScreen(), overrides: clubOverrides()));
      await tester.pumpAndSettle();

      // Dans l'AppBar (jamais hors écran), en plus du bouton texte en bas de liste.
      final appBar = find.ancestor(of: find.byKey(const Key('sign-out')), matching: find.byType(AppBar));
      expect(appBar, findsOneWidget);
    });

    testWidgets('le super coach voit les demandes de coach et peut approuver', (tester) async {
      final fake = FakeClubActions();
      final requests = [
        membership(id: 'r1', userId: 'u2', role: ClubRole.coach, active: false, name: 'Marc'),
        membership(id: 'r2', userId: 'u3', role: ClubRole.athlete, active: false, name: 'Léa'),
      ];
      await tester.pumpWidget(testApp(const ClubScreen(), overrides: clubOverrides(requests: requests, clubActions: fake)));
      await tester.pumpAndSettle();

      expect(find.text('Demandes en attente'), findsOneWidget);
      await tester.tap(find.byKey(const Key('approve-Marc')));
      expect(fake.approved, ['r1']);
    });

    testWidgets('un simple coach ne peut pas valider une demande de coach', (tester) async {
      final requests = [
        membership(id: 'r1', userId: 'u2', role: ClubRole.coach, active: false, name: 'Marc'),
        membership(id: 'r2', userId: 'u3', role: ClubRole.athlete, active: false, name: 'Léa'),
      ];
      final fake = FakeClubActions();
      final overrides = clubOverrides(me: membership(role: ClubRole.coach), requests: requests, clubActions: fake);
      await tester.pumpWidget(testApp(const ClubScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('approve-Marc')), findsNothing);
      expect(find.byKey(const Key('approve-Léa')), findsOneWidget);
      await tester.tap(find.byKey(const Key('approve-Léa')));
      expect(fake.approved, ['r2']);
      expect(find.textContaining('seul le super coach'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Se déconnecter'), 300);
      expect(find.text('Quitter le club'), findsOneWidget, reason: 'un coach peut partir');
    });

    testWidgets('le super coach ne peut pas quitter sans passer la main', (tester) async {
      await tester.pumpWidget(testApp(const ClubScreen(), overrides: clubOverrides()));
      await tester.pumpAndSettle();
      // On descend jusqu'au pied de page : sans cela, l'absence pourrait venir de la liste paresseuse.
      await tester.scrollUntilVisible(find.text('Se déconnecter'), 300);
      expect(find.text('Quitter le club'), findsNothing);
    });

    testWidgets('groupes, athlètes et compteurs', (tester) async {
      const lea = Athlete(id: 'a1', fullName: 'Léa Martin', userId: 'u3');
      const tom = Athlete(id: 'a2', fullName: 'Tom Durand');
      final overrides = clubOverrides(
        athletes: const [lea, tom],
        links: {'a1': {sprintGroup.id}, 'a2': {sprintGroup.id, demiGroup.id}},
      );
      await tester.pumpWidget(testApp(const ClubScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      expect(find.text('2 athlètes'), findsOneWidget, reason: 'Sprint compte Léa et Tom');
      expect(find.text('1 athlète'), findsOneWidget, reason: 'Demi-fond compte Tom seul');
      expect(find.text('Compte lié · 1 groupe'), findsOneWidget);
      expect(find.text('Pas encore de compte · 2 groupes'), findsOneWidget);
    });

    testWidgets('un coach voit en lecture seule le profil d’un athlète lié', (tester) async {
      const lea = Athlete(id: 'a1', fullName: 'Léa Martin', userId: 'u3');
      const record = AthleteRecord(id: 'r1', athleteId: 'a1', discipline: '10 km', performance: '38:12');
      final overrides = clubOverrides(
        athletes: const [lea],
        athleteProfiles: {'a1': const AthleteProfile(athleteId: 'a1', bio: 'Toujours partante pour un footing.')},
        athleteRecords: {
          'a1': [record],
        },
      );
      await tester.pumpWidget(testApp(const ClubScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Léa Martin'));
      await tester.pumpAndSettle();

      expect(find.text('Toujours partante pour un footing.'), findsOneWidget);
      expect(find.text('10 km — 38:12'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing, reason: 'lecture seule pour le coach');
    });
  });

  group('rejoindre un club : recherche', () {
    Future<void> openSearchTab(WidgetTester tester, FakeClubActions fake) async {
      await tester.pumpWidget(testApp(const JoinClubScreen(), overrides: clubOverrides(clubActions: fake)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chercher un club'));
      await tester.pumpAndSettle();
    }

    testWidgets('moins de 2 caractères : pas de recherche', (tester) async {
      final fake = FakeClubActions();
      await openSearchTab(tester, fake);

      await tester.enterText(find.byKey(const Key('club-search')), 's');
      await tester.pump(const Duration(milliseconds: 400));
      expect(fake.searchedQueries, isEmpty);
    });

    testWidgets('dès 2 caractères : recherche en direct et affiche les résultats', (tester) async {
      final fake = FakeClubActions()..searchResults = const [Club(id: 'c1', name: 'Senlis Athlé')];
      await openSearchTab(tester, fake);

      await tester.enterText(find.byKey(const Key('club-search')), 'se');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(fake.searchedQueries, ['se']);
      expect(find.text('Senlis Athlé'), findsOneWidget);
    });

    testWidgets('toucher un club affiche le choix de rôle, puis envoie la demande', (tester) async {
      final fake = FakeClubActions()..searchResults = const [Club(id: 'c1', name: 'Senlis Athlé')];
      await openSearchTab(tester, fake);

      await tester.enterText(find.byKey(const Key('club-search')), 'senlis');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Senlis Athlé'));
      await tester.pumpAndSettle();
      expect(find.text('Je rejoins en tant que…'), findsOneWidget);

      await tester.tap(find.byKey(const Key('join-request')));
      await tester.pumpAndSettle();
      expect(fake.joinRequests, [('c1', ClubRole.athlete)]);
    });
  });

  group('profil athlète', () {
    testWidgets('accès direct à la déconnexion dans l’AppBar', (tester) async {
      await tester.pumpWidget(testApp(const ProfileScreen(), overrides: clubOverrides()));
      await tester.pumpAndSettle();

      final appBar = find.ancestor(of: find.byKey(const Key('sign-out')), matching: find.byType(AppBar));
      expect(appBar, findsOneWidget);
    });

    testWidgets('un athlète rejoint et quitte librement un groupe', (tester) async {
      final planning = FakePlanning();
      const me = Athlete(id: 'a1', fullName: 'Léa', userId: 'u-julie');
      final overrides = clubOverrides(
        me: membership(role: ClubRole.athlete),
        planning: planning,
        athletes: const [me],
        links: {'a1': {sprintGroup.id}},
      );
      await tester.pumpWidget(testApp(const ProfileScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      // Le champ description a lui-même un Scrollable interne : on précise lequel faire défiler.
      await tester.scrollUntilVisible(
        find.byKey(const Key('my-group-Demi-fond')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('my-group-Demi-fond')));
      await tester.tap(find.byKey(const Key('my-group-Sprint')));
      expect(planning.groupToggles, [(demiGroup.id, true), (sprintGroup.id, false)]);
    });

    testWidgets('modifier la description et le lien FFA les enregistre', (tester) async {
      const me = Athlete(id: 'a1', fullName: 'Léa', userId: 'u-julie');
      final fake = FakeProfileActions();
      final overrides = clubOverrides(
        me: membership(role: ClubRole.athlete),
        athletes: const [me],
        profileActions: fake,
      );
      await tester.pumpWidget(testApp(const ProfileScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('bio-field')), 'Coureuse de fond, sourire garanti.');
      await tester.enterText(find.byKey(const Key('ffa-field')), 'www.athle.fr/athletes/95743/records');
      await tester.tap(find.byKey(const Key('save-profile')));
      await tester.pumpAndSettle();

      expect(fake.savedProfiles, [
        ('a1', 'Coureuse de fond, sourire garanti.', 'www.athle.fr/athletes/95743/records'),
      ]);
    });

    testWidgets('ajouter un record personnel', (tester) async {
      const me = Athlete(id: 'a1', fullName: 'Léa', userId: 'u-julie');
      final fake = FakeProfileActions();
      final overrides = clubOverrides(
        me: membership(role: ClubRole.athlete),
        athletes: const [me],
        profileActions: fake,
      );
      await tester.pumpWidget(testApp(const ProfileScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-record')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('record-discipline')), '10 km');
      await tester.pump();
      await tester.enterText(find.byKey(const Key('record-performance')), '38:12');
      await tester.pump();
      await tester.tap(find.byKey(const Key('record-save')));
      await tester.pumpAndSettle();

      expect(fake.savedRecords, hasLength(1));
      expect(fake.savedRecords.single.discipline, '10 km');
      expect(fake.savedRecords.single.performance, '38:12');
      expect(find.byKey(const Key('record-discipline')), findsNothing, reason: 'la feuille se ferme après l’ajout');
    });

    testWidgets('supprimer un record demande confirmation', (tester) async {
      const me = Athlete(id: 'a1', fullName: 'Léa', userId: 'u-julie');
      const record = AthleteRecord(id: 'r1', athleteId: 'a1', discipline: '100 m', performance: '13.1');
      final fake = FakeProfileActions();
      final overrides = clubOverrides(
        me: membership(role: ClubRole.athlete),
        athletes: const [me],
        athleteRecords: {
          'a1': [record],
        },
        profileActions: fake,
      );
      await tester.pumpWidget(testApp(const ProfileScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('100 m — 13.1'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
      await tester.pumpAndSettle();

      expect(fake.deletedRecords, ['r1']);
    });
  });

  group('connexion et onboarding', () {
    testWidgets('validation du formulaire de connexion', (tester) async {
      await tester.pumpWidget(testApp(const AuthScreen(), overrides: [userProvider.overrideWithValue(null)]));
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pump();
      expect(find.text('Email invalide'), findsOneWidget);
      expect(find.byKey(const Key('auth-name')), findsNothing, reason: 'pas de nom à la connexion');

      await tester.tap(find.text('Créer un compte'));
      await tester.pump();
      expect(find.byKey(const Key('auth-name')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('auth-email')), 'julie@example.com');
      await tester.enterText(find.byKey(const Key('auth-password')), 'court');
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pump();
      expect(find.text('Indique ton nom'), findsOneWidget);
      expect(find.text('8 caractères minimum'), findsWidgets);
    });

    testWidgets('onboarding : créer ou rejoindre, avec le prénom', (tester) async {
      await tester.pumpWidget(testApp(const OnboardingScreen(), overrides: [userProvider.overrideWithValue(testUser)]));
      expect(find.text('Bienvenue Julie'), findsOneWidget);
      expect(find.byKey(const Key('choice-create')), findsOneWidget);
      expect(find.byKey(const Key('choice-join')), findsOneWidget);
    });
  });
}
