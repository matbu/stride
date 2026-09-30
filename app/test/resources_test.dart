import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:trackclub/core/format.dart';
import 'package:trackclub/data/models.dart';
import 'package:trackclub/features/library/library_screen.dart';
import 'package:trackclub/features/planning/session_detail.dart';
import 'package:trackclub/features/planning/session_editor.dart';
import 'package:trackclub/features/resources/resources_screen.dart';

import 'helpers.dart';

const gammes = Resource(
  id: 'r-gammes',
  clubId: 'c1',
  kind: ResourceKind.instagram,
  title: 'Gammes athlétiques',
  url: 'https://www.instagram.com/reel/abc/',
);
const blocs = Resource(
  id: 'r-blocs',
  clubId: 'c1',
  kind: ResourceKind.youtube,
  title: 'Posture en starting-blocks',
  url: 'https://youtu.be/xyz',
  isPublic: true,
);

void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('modèles', () {
    test('nature d’un lien d’après son hôte', () {
      expect(ResourceKind.ofUrl(Uri.parse('https://youtu.be/abc')), ResourceKind.youtube);
      expect(ResourceKind.ofUrl(Uri.parse('https://m.youtube.com/watch?v=abc')), ResourceKind.youtube);
      expect(ResourceKind.ofUrl(Uri.parse('https://www.instagram.com/reel/abc/')), ResourceKind.instagram);
      expect(ResourceKind.ofUrl(Uri.parse('https://athle.fr')), ResourceKind.link);
    });

    test('id de vidéo YouTube : lien court, watch, shorts', () {
      expect(youtubeVideoId(Uri.parse('https://youtu.be/abc123')), 'abc123');
      expect(youtubeVideoId(Uri.parse('https://www.youtube.com/watch?v=abc123&t=4')), 'abc123');
      expect(youtubeVideoId(Uri.parse('https://youtube.com/shorts/abc123')), 'abc123');
      expect(youtubeVideoId(Uri.parse('https://youtube.com/@club')), isNull);
    });

    test('resource_ids : JSON en texte, vide si absent', () {
      expect(decodeResourceIds('["a","b"]'), ['a', 'b']);
      expect(decodeResourceIds(null), isEmpty);
      expect(decodeResourceIds(''), isEmpty);
    });
  });

  group('bibliothèque', () {
    testWidgets('deux listes dépliables : séances et ressources', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(testApp(const LibraryScreen(), overrides: clubOverrides(resources: [gammes, blocs])));
      await tester.pumpAndSettle();
      expect(find.text('Séances (0)'), findsOneWidget);
      expect(find.text('Ressources (2)'), findsOneWidget);
      expect(find.text('Gammes athlétiques'), findsOneWidget);
      expect(find.textContaining('Publique'), findsOneWidget, reason: 'la confidentialité est affichée au coach');

      // Replier la liste des ressources la masque.
      await tester.tap(find.text('Ressources (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Gammes athlétiques'), findsNothing);
    });

    testWidgets('ajouter un lien exige de choisir la confidentialité', (tester) async {
      tallScreen(tester);
      final fake = FakeResourceActions();
      await tester.pumpWidget(testApp(const LibraryScreen(), overrides: clubOverrides(resourceActions: fake)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-template')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-add-resource')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-resource-link')));
      await tester.pumpAndSettle();

      FilledButton save() => tester.widget<FilledButton>(find.byKey(const Key('resource-save')));
      await tester.enterText(find.byKey(const Key('resource-url')), 'instagram.com/reel/abc');
      await tester.enterText(find.byKey(const Key('resource-title')), 'Gammes');
      await tester.pump();
      expect(save().onPressed, isNull, reason: 'confidentialité non choisie');

      await tester.tap(find.text('Mon club'));
      await tester.pump();
      expect(save().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('resource-save')));
      await tester.pumpAndSettle();

      expect(fake.links.single, (url: 'https://instagram.com/reel/abc', title: 'Gammes', isPublic: false));
    });

    testWidgets('un lien déjà public ailleurs : proposer de l’ajouter tel quel', (tester) async {
      tallScreen(tester);
      final fake = FakeResourceActions()..publicMatch = blocs;
      await tester.pumpWidget(testApp(const LibraryScreen(), overrides: clubOverrides(resourceActions: fake)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-template')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-add-resource')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-resource-link')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('resource-url')), 'https://youtu.be/xyz');
      await tester.enterText(find.byKey(const Key('resource-title')), 'Blocs');
      await tester.tap(find.text('Public'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('resource-save')));
      await tester.pumpAndSettle();

      expect(find.text('Déjà partagée publiquement'), findsOneWidget);
      await tester.tap(find.text('Ajouter celle-ci'));
      await tester.pumpAndSettle();
      expect(fake.addedPublic, [blocs.id]);
      expect(fake.links, isEmpty);
    });

    testWidgets('supprimer une ressource demande confirmation', (tester) async {
      tallScreen(tester);
      final fake = FakeResourceActions();
      await tester.pumpWidget(
          testApp(const LibraryScreen(), overrides: clubOverrides(resources: [gammes], resourceActions: fake)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resource-menu-Gammes athlétiques')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resource-delete')));
      await tester.pumpAndSettle();
      expect(fake.deleted, isEmpty);
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(fake.deleted, [gammes.id]);
    });
  });

  group('séances', () {
    testWidgets('joindre une ressource à une séance', (tester) async {
      tallScreen(tester);
      final fake = FakeSessions();
      await tester.pumpWidget(testApp(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => openSessionEditor(context, newSessionDraft(date: DateTime(2026, 9, 28))),
              child: const Text('ouvrir'),
            ),
          ),
        ),
        overrides: clubOverrides(sessionActions: fake, resources: [gammes, blocs]),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('type-Fractionné')));
      await tester.enterText(find.byKey(const Key('session-title')), 'Vitesse');
      await tester.tap(find.byKey(const Key('group-Sprint')));
      await tester.ensureVisible(find.byKey(const Key('session-add-resource')));
      await tester.tap(find.byKey(const Key('session-add-resource')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-resource-Posture en starting-blocks')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('picker-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Posture en starting-blocks'), findsOneWidget, reason: 'affichée dans l’éditeur');

      await tester.tap(find.byKey(const Key('session-save')));
      await tester.pumpAndSettle();
      expect(fake.saved.single.resourceIds, [blocs.id]);
    });

    testWidgets('un athlète voit les ressources de sa séance, pas celles supprimées', (tester) async {
      tallScreen(tester);
      final session = PlannedSession(
        id: 's1',
        typeId: fractionne.id,
        title: 'Vitesse',
        groupId: sprintGroup.id,
        date: isoDate(DateTime(2026, 9, 28)),
        resourceIds: const ['r-blocs', 'r-supprimee'],
      );
      await tester.pumpWidget(testApp(
        SessionDetailScreen(session: session, type: fractionne),
        overrides: clubOverrides(me: membership(role: ClubRole.athlete), resources: [gammes, blocs]),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Ressources'), findsOneWidget);
      expect(find.text('Posture en starting-blocks'), findsOneWidget);
      expect(find.text('Gammes athlétiques'), findsNothing, reason: 'non attachée à cette séance');
    });
  });

  testWidgets('un athlète consulte les ressources en lecture seule', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(testApp(
      const ResourcesScreen(),
      overrides: clubOverrides(me: membership(role: ClubRole.athlete), resources: [gammes]),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Gammes athlétiques'), findsOneWidget);
    expect(find.byKey(const Key('resource-menu-Gammes athlétiques')), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
