import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:trackclub/core/format.dart';
import 'package:trackclub/data/models.dart';
import 'package:trackclub/features/season/season_screen.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  final tomorrow = isoDate(addDays(dateOnly(DateTime.now()), 1));
  final yesterday = isoDate(addDays(dateOnly(DateTime.now()), -1));

  group('saison', () {
    testWidgets('aucun événement : message pour un coach, avec bouton d’ajout', (tester) async {
      await tester.pumpWidget(testApp(const SeasonScreen(), overrides: clubOverrides()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Aucun événement'), findsOneWidget);
      expect(find.byKey(const Key('add-event')), findsOneWidget);
    });

    testWidgets('un athlète ne voit pas le bouton d’ajout', (tester) async {
      final overrides = clubOverrides(me: membership(role: ClubRole.athlete));
      await tester.pumpWidget(testApp(const SeasonScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add-event')), findsNothing);
    });

    testWidgets('affiche un événement à venir, avec ses groupes concernés', (tester) async {
      final overrides = clubOverrides(
        events: [Event(id: 'e1', kind: EventKind.competition, title: 'Régionaux', startDate: tomorrow, endDate: tomorrow)],
        eventGroups: {
          'e1': {sprintGroup.id},
        },
      );
      await tester.pumpWidget(testApp(const SeasonScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      expect(find.text('Régionaux'), findsOneWidget);
      expect(find.textContaining('Sprint'), findsOneWidget);
    });

    testWidgets('sans groupe précisé, « Tout le club »', (tester) async {
      final overrides = clubOverrides(
        events: [Event(id: 'e1', kind: EventKind.deadline, title: 'Dossier CACI', startDate: tomorrow, endDate: tomorrow)],
      );
      await tester.pumpWidget(testApp(const SeasonScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      expect(find.textContaining('Tout le club'), findsOneWidget);
    });

    testWidgets('sépare les événements passés des événements à venir', (tester) async {
      final overrides = clubOverrides(
        events: [
          Event(id: 'e1', kind: EventKind.competition, title: 'Passé', startDate: yesterday, endDate: yesterday),
          Event(id: 'e2', kind: EventKind.competition, title: 'Futur', startDate: tomorrow, endDate: tomorrow),
        ],
      );
      await tester.pumpWidget(testApp(const SeasonScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      expect(find.text('À venir'), findsOneWidget);
      expect(find.text('Passés'), findsOneWidget);
      expect(find.text('Futur'), findsOneWidget);
      expect(find.text('Passé'), findsOneWidget);
    });

    testWidgets('un coach crée un événement', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeEventActions();
      await tester.pumpWidget(testApp(const SeasonScreen(), overrides: clubOverrides(eventActions: fake)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-event')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('event-title')), 'Régionaux');
      await tester.pump();
      await tester.tap(find.text('Stage'));
      await tester.pump();
      await tester.tap(find.byKey(Key('event-group-${sprintGroup.name}')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();

      expect(fake.saved, hasLength(1));
      expect(fake.saved.single.title, 'Régionaux');
      expect(fake.saved.single.kind, EventKind.camp);
      expect(fake.saved.single.groupIds, {sprintGroup.id});
    });

    testWidgets('un coach modifie un événement existant, avec option de suppression', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeEventActions();
      final overrides = clubOverrides(
        events: [Event(id: 'e1', kind: EventKind.competition, title: 'Régionaux', startDate: tomorrow, endDate: tomorrow)],
        eventActions: fake,
      );
      await tester.pumpWidget(testApp(const SeasonScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Régionaux'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('event-title')), findsOneWidget, reason: 'un coach édite, il ne lit pas juste');
      await tester.ensureVisible(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Supprimer').last);
      await tester.pumpAndSettle();

      expect(fake.deleted, ['e1']);
    });

    testWidgets('un athlète voit le détail en lecture seule, sans pouvoir modifier', (tester) async {
      final overrides = clubOverrides(
        me: membership(role: ClubRole.athlete),
        events: [
          Event(
            id: 'e1', kind: EventKind.competition, title: 'Régionaux', startDate: tomorrow, endDate: tomorrow,
            location: 'Stade municipal', notes: 'Prévoir les licences.',
          ),
        ],
      );
      await tester.pumpWidget(testApp(const SeasonScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Régionaux'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('event-title')), findsNothing, reason: 'lecture seule pour un athlète');
      expect(find.text('Stade municipal'), findsOneWidget);
      expect(find.text('Prévoir les licences.'), findsOneWidget);
    });
  });
}
