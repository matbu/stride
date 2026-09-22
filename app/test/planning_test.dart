import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:coach/core/format.dart';
import 'package:coach/core/notation.dart';
import 'package:coach/data/drafts.dart';
import 'package:coach/data/import_csv.dart';
import 'package:coach/data/models.dart';
import 'package:coach/features/library/import_screen.dart';
import 'package:coach/features/library/library_screen.dart';
import 'package:coach/features/planning/block_card.dart';
import 'package:coach/features/planning/session_editor.dart';
import 'package:coach/features/planning/week_screen.dart';

import 'helpers.dart';

/// Écran haut : l'éditeur est une longue liste, on évite de faire défiler dans les tests.
void tallScreen(WidgetTester tester, {double width = 900, double height = 2600}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Ouvre l'éditeur par-dessus une page d'accueil, comme dans l'app (il peut ainsi se refermer).
Future<void> openEditor(WidgetTester tester, SessionDraft draft, List<Override> overrides) async {
  await tester.pumpWidget(testApp(
    Builder(
      builder: (context) => Center(
        child: TextButton(onPressed: () => openSessionEditor(context, draft), child: const Text('ouvrir')),
      ),
    ),
    overrides: overrides,
  ));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  final today = dateOnly(DateTime.now());
  final todayIso = isoDate(today);

  group('éditeur de séance', () {
    testWidgets('saisie rapide : « 10x400 r1\' 3x300 r1\' » crée deux exercices', (tester) async {
      tallScreen(tester);
      final fake = FakeSessions();
      await openEditor(tester, newSessionDraft(date: DateTime(2026, 9, 28)), clubOverrides(sessionActions: fake));

      expect(find.byKey(const Key('session-save')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('session-save'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('type-Fractionné')));
      await tester.enterText(find.byKey(const Key('session-title')), '10 × 400 + 3 × 300');
      await tester.tap(find.byKey(const Key('group-Sprint')));
      // Bloc 1 = corps de séance (les blocs par défaut sont échauffement, corps, retour au calme).
      await tester.enterText(find.byKey(const Key('quick-input-1')), "10x400 r1' 3x300 r1'");
      await tester.pump();

      // L'aperçu montre ce qui a été compris, avant l'ajout.
      expect(find.text("10 × 400 m · récup 1'"), findsOneWidget);
      expect(find.text("3 × 300 m · récup 1'"), findsOneWidget);

      await tester.tap(find.byKey(const Key('quick-add-1')));
      await tester.pump();
      expect(find.text("10 × 400 m · récup 1'"), findsOneWidget, reason: 'devenu une ligne de la liste');
      expect(find.text('4,9 km'), findsWidgets, reason: 'volume du bloc : 4000 + 900');

      await tester.tap(find.byKey(const Key('session-save')));
      await tester.pumpAndSettle();

      expect(fake.saved, hasLength(1));
      final d = fake.saved.single;
      expect(d.typeId, fractionne.id);
      expect(d.title, '10 × 400 + 3 × 300');
      expect(d.groupIds, {sprintGroup.id});
      expect(d.date, '2026-09-28');
      expect(d.blocks, hasLength(1), reason: 'les blocs vides ne sont pas enregistrés');
      expect(d.blocks.single.kind, BlockKind.main);
      expect(d.blocks.single.items, [
        const BlockItem(reps: 10, distanceM: 400, recoveryS: 60),
        const BlockItem(reps: 3, distanceM: 300, recoveryS: 60),
      ]);
      expect(find.byKey(const Key('session-save')), findsNothing, reason: 'l’éditeur se ferme');
    });

    testWidgets('les raccourcis du clavier insèrent au curseur', (tester) async {
      tallScreen(tester);
      await openEditor(tester, newSessionDraft(), clubOverrides());
      expect(find.widgetWithText(ActionChip, 'r'), findsNothing, reason: 'cachés tant qu’on ne saisit pas');
      await tester.enterText(find.byKey(const Key('quick-input-1')), '10x400 ');
      await tester.pump();
      expect(find.widgetWithText(ActionChip, 'r'), findsOneWidget, reason: 'sous le seul champ actif');
      await tester.tap(find.widgetWithText(ActionChip, 'r'));
      await tester.tap(find.widgetWithText(ActionChip, "'"));
      await tester.pump();
      expect(find.text("10x400 r'"), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'r'), findsOneWidget, reason: 'le champ garde le focus');
    });

    testWidgets('un exercice se modifie avec la même notation, et se supprime', (tester) async {
      tallScreen(tester);
      final fake = FakeSessions();
      const session = PlannedSession(
        id: 's-42', typeId: 't-frac', title: 'Piste', groupId: 'g-sprint', date: '2026-09-28',
      );
      final blocks = {
        's-42': const [
          SessionBlock(
            id: 'b1', sessionId: 's-42', kind: BlockKind.main, position: 0, title: '', notes: '',
            items: [BlockItem(reps: 6, distanceM: 400, recoveryS: 90), BlockItem(note: 'Étirements')],
          ),
        ],
      };
      await openEditor(tester, SessionDraft.fromPlanned(session), clubOverrides(blocks: blocks, sessionActions: fake));

      expect(find.text("6 × 400 m · récup 1'30"), findsOneWidget, reason: 'blocs chargés depuis la base');
      expect(find.text('Étirements'), findsOneWidget);

      await tester.tap(find.text("6 × 400 m · récup 1'30"));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-item')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('edit-item')), "8x400 r1'");
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text("8 × 400 m · récup 1'"), findsOneWidget);

      await tester.tap(find.byTooltip('Supprimer l’exercice').last);
      await tester.pump();
      expect(find.text('Étirements'), findsNothing);

      await tester.tap(find.byKey(const Key('session-save')));
      await tester.pumpAndSettle();
      final d = fake.saved.single;
      expect(d.id, 's-42', reason: 'mise à jour de la séance existante');
      expect(d.blocks.single.id, 'b1', reason: 'le bloc existant est conservé, pas recréé');
      expect(d.blocks.single.items, [const BlockItem(reps: 8, distanceM: 400, recoveryS: 60)]);
    });

    testWidgets('on peut ajouter un bloc à la bonne place', (tester) async {
      tallScreen(tester);
      await openEditor(tester, newSessionDraft(), clubOverrides());
      Finder heading(String t) => find.text(t);
      expect(heading('Échauffement'), findsWidgets);
      await tester.tap(find.byKey(const Key('add-block-other')));
      await tester.pump();
      // « Autre » s'insère avant le retour au calme.
      final blockHeading = find.descendant(of: find.byType(BlockCard), matching: heading('Autre'));
      expect(blockHeading, findsOneWidget);
      final other = tester.getTopLeft(blockHeading).dy;
      final cooldown = tester.getTopLeft(heading('Retour au calme').first).dy;
      expect(other < cooldown, isTrue);
    });

    testWidgets('quitter avec des modifications demande confirmation', (tester) async {
      tallScreen(tester);
      await openEditor(tester, newSessionDraft(), clubOverrides());

      await tester.enterText(find.byKey(const Key('session-title')), 'Brouillon');
      await tester.pump();
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);

      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session-title')), findsOneWidget, reason: 'reste dans l’éditeur');

      nav.maybePop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session-title')), findsNothing);
    });

    testWidgets('quitter sans modification ne demande rien', (tester) async {
      tallScreen(tester);
      await openEditor(tester, newSessionDraft(), clubOverrides());
      tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Abandonner les modifications ?'), findsNothing);
      expect(find.byKey(const Key('session-title')), findsNothing);
    });

    testWidgets('un modèle n’a ni groupe ni date', (tester) async {
      tallScreen(tester);
      final fake = FakeSessions();
      await openEditor(tester, newSessionDraft(template: true), clubOverrides(sessionActions: fake));
      expect(find.text('Nouveau modèle'), findsOneWidget);
      expect(find.byKey(const Key('group-Sprint')), findsNothing);

      await tester.tap(find.byKey(const Key('type-Endurance')));
      await tester.enterText(find.byKey(const Key('session-title')), 'Footing 1h');
      await tester.pump();
      await tester.tap(find.byKey(const Key('session-save')));
      await tester.pumpAndSettle();

      final d = fake.saved.single;
      expect(d.isTemplate, isTrue);
      expect(d.groupIds, isEmpty);
      expect(d.date, isNull);
    });

    testWidgets('création sur plusieurs groupes : un seul brouillon, le serveur crée une séance par groupe',
        (tester) async {
      tallScreen(tester);
      final fake = FakeSessions();
      await openEditor(tester, newSessionDraft(), clubOverrides(sessionActions: fake));
      await tester.tap(find.byKey(const Key('type-Endurance')));
      await tester.enterText(find.byKey(const Key('session-title')), 'Footing');
      await tester.tap(find.byKey(const Key('group-Sprint')));
      await tester.tap(find.byKey(const Key('group-Demi-fond')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('session-save')));
      await tester.pumpAndSettle();
      expect(fake.saved.single.groupIds, {sprintGroup.id, demiGroup.id});
    });
  });

  group('bibliothèque', () {
    const tpl = Template(id: 'tpl-1', typeId: 't-frac', title: '10 × 400', durationMin: 90);

    testWidgets('liste les modèles et propose de les placer', (tester) async {
      final fake = FakeSessions();
      await tester.pumpWidget(testApp(const LibraryScreen(), overrides: clubOverrides(templates: [tpl], sessionActions: fake)));
      await tester.pumpAndSettle();
      expect(find.text('10 × 400'), findsOneWidget);
      expect(find.text('Fractionné'), findsWidgets);
      expect(find.text('90 min'), findsOneWidget);

      await tester.tap(find.byKey(const Key('template-10 × 400')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tpl-place')));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(find.byKey(const Key('place-confirm'))).onPressed, isNull,
          reason: 'il faut au moins un groupe');
      await tester.tap(find.byKey(const Key('place-group-Sprint')));
      await tester.tap(find.byKey(const Key('place-group-Demi-fond')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('place-confirm')));
      await tester.pumpAndSettle();

      final placed = fake.placed.single;
      expect(placed.templateId, 'tpl-1');
      expect(placed.groups, {sprintGroup.id, demiGroup.id});
      expect(placed.date, todayIso);
    });

    testWidgets('bibliothèque vide : message et création possible', (tester) async {
      await tester.pumpWidget(testApp(const LibraryScreen(), overrides: clubOverrides()));
      await tester.pumpAndSettle();
      expect(find.text('Ta bibliothèque est vide'), findsOneWidget);
      expect(find.byKey(const Key('new-template')), findsOneWidget);
    });

    testWidgets('suppression d’un modèle avec confirmation', (tester) async {
      final fake = FakeSessions();
      await tester.pumpWidget(testApp(const LibraryScreen(), overrides: clubOverrides(templates: [tpl], sessionActions: fake)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('template-10 × 400')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tpl-delete')));
      await tester.pumpAndSettle();
      expect(fake.deleted, isEmpty, reason: 'pas avant la confirmation');
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(fake.deleted, ['tpl-1']);
    });
  });

  group('import CSV', () {
    List<Override> overrides(FakeSessions fake) =>
        clubOverrides(types: const [fractionne, endurance, seuil], sessionActions: fake);

    testWidgets('aperçu puis import du fichier modèle', (tester) async {
      tallScreen(tester);
      final fake = FakeSessions();
      await tester.pumpWidget(testApp(const ImportScreen(), overrides: overrides(fake)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('import-paste')), importTemplateCsv);
      await tester.tap(find.byKey(const Key('import-analyse')));
      await tester.pumpAndSettle();

      expect(find.text('3 prête(s)'), findsOneWidget);
      expect(find.textContaining('Modèle de bibliothèque'), findsOneWidget);
      expect(find.text('Importer 3 séances'), findsOneWidget);

      await tester.tap(find.byKey(const Key('import-confirm')));
      await tester.pumpAndSettle();
      expect(fake.saved, hasLength(3));
      final first = fake.saved.first;
      expect(first.date, '2026-09-28');
      expect(first.startTime, '18:30');
      expect(first.groupIds, {sprintGroup.id, demiGroup.id});
      expect(first.blocks.map((b) => b.kind), [BlockKind.warmup, BlockKind.main, BlockKind.cooldown]);
      expect(first.blocks[1].items, [
        const BlockItem(reps: 10, distanceM: 400, recoveryS: 60),
        const BlockItem(reps: 3, distanceM: 300, recoveryS: 60),
      ]);
      expect(fake.saved.last.isTemplate, isTrue);
    });

    testWidgets('les lignes invalides sont signalées et ignorées', (tester) async {
      tallScreen(tester);
      final fake = FakeSessions();
      await tester.pumpWidget(testApp(const ImportScreen(), overrides: overrides(fake)));
      await tester.pumpAndSettle();

      const csv = 'date;groupes;type;titre;corps\n'
          '2026-09-28;Sprint;Fractionné;Bonne ligne;10x400 r1\'\n'
          '2026-09-29;Sprint;Inconnu;Mauvais type;\n'
          '2026-09-30;Fantôme;Fractionné;Mauvais groupe;\n';
      await tester.enterText(find.byKey(const Key('import-paste')), csv);
      await tester.tap(find.byKey(const Key('import-analyse')));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 prête(s)'), findsOneWidget);
      expect(find.textContaining('2 à corriger'), findsOneWidget);
      expect(find.textContaining('type inconnu « Inconnu »'), findsOneWidget);
      expect(find.textContaining('groupe inconnu « Fantôme »'), findsOneWidget);

      await tester.tap(find.byKey(const Key('import-confirm')));
      await tester.pumpAndSettle();
      expect(fake.saved.map((d) => d.title), ['Bonne ligne']);
    });

    testWidgets('sans ligne valide, pas de bouton d’import', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(testApp(const ImportScreen(), overrides: overrides(FakeSessions())));
      await tester.enterText(find.byKey(const Key('import-paste')), 'colonne;autre\n1;2\n');
      await tester.tap(find.byKey(const Key('import-analyse')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Colonne(s) obligatoire(s) absente(s)'), findsOneWidget);
      expect(find.byKey(const Key('import-confirm')), findsNothing);
    });
  });

  group('vue semaine en 7 colonnes', () {
    // Deux jours distincts de la semaine courante.
    final monday = mondayOf(today);
    final dayA = isoDate(monday);
    final dayB = isoDate(addDays(monday, 2));
    PlannedSession session(String id, String date, String title) => PlannedSession(
          id: id, typeId: fractionne.id, title: title, groupId: sprintGroup.id, date: date,
        );

    testWidgets('téléphone : un seul jour à la fois', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(testApp(const WeekScreen(), overrides: clubOverrides()));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('day-$dayA')), findsNothing);
    });

    testWidgets('tablette : 7 colonnes avec les séances au bon jour', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sessions = [session('s1', dayA, 'Lundi dur'), session('s2', dayB, 'Mercredi doux')];
      await tester.pumpWidget(testApp(const WeekScreen(), overrides: clubOverrides(sessions: sessions)));
      await tester.pumpAndSettle();

      for (var i = 0; i < 7; i++) {
        expect(find.byKey(Key('day-${isoDate(addDays(monday, i))}')), findsOneWidget);
        expect(find.byKey(Key('add-${isoDate(addDays(monday, i))}')), findsOneWidget, reason: '+ par jour');
      }
      // Chaque séance est dans la colonne de son jour.
      Finder inDay(String iso, String title) =>
          find.descendant(of: find.byKey(Key('day-$iso')), matching: find.text(title));
      expect(inDay(dayA, 'Lundi dur'), findsOneWidget);
      expect(inDay(dayB, 'Mercredi doux'), findsOneWidget);
      expect(inDay(dayA, 'Mercredi doux'), findsNothing);
    });

    testWidgets('tablette : glisser une séance sur un autre jour la déplace', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeSessions();
      await tester.pumpWidget(testApp(
        const WeekScreen(),
        overrides: clubOverrides(sessions: [session('s1', dayA, 'À déplacer')], sessionActions: fake),
      ));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getCenter(find.text('À déplacer')));
      await tester.pump(const Duration(milliseconds: 600)); // appui long
      await gesture.moveTo(tester.getCenter(find.byKey(Key('day-$dayB'))));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(tester.getCenter(find.byKey(Key('day-$dayB'))) + const Offset(0, 4));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fake.moved, [('s1', dayB)]);
    });

    testWidgets('tablette : déposer sur son propre jour ne fait rien', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeSessions();
      await tester.pumpWidget(testApp(
        const WeekScreen(),
        overrides: clubOverrides(sessions: [session('s1', dayA, 'Reste ici')], sessionActions: fake),
      ));
      await tester.pumpAndSettle();
      final start = tester.getCenter(find.text('Reste ici'));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(start + const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fake.moved, isEmpty);
    });

    testWidgets('téléphone : glisser une séance sur un autre jour la déplace', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeSessions();
      final target = addDays(today, 1);
      await tester.pumpWidget(testApp(
        const WeekScreen(),
        overrides: clubOverrides(sessions: [session('s1', isoDate(today), 'À déplacer')], sessionActions: fake),
      ));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getCenter(find.text('À déplacer')));
      await tester.pump(const Duration(milliseconds: 600)); // appui long
      await gesture.moveTo(tester.getCenter(find.byKey(Key('day-strip-${isoDate(target)}'))));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(tester.getCenter(find.byKey(Key('day-strip-${isoDate(target)}'))) + const Offset(0, 4));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fake.moved, [('s1', isoDate(target))]);
    });

    testWidgets('téléphone : déposer sur son propre jour ne fait rien', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeSessions();
      await tester.pumpWidget(testApp(
        const WeekScreen(),
        overrides: clubOverrides(sessions: [session('s1', isoDate(today), 'Reste ici')], sessionActions: fake),
      ));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getCenter(find.text('Reste ici')));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(tester.getCenter(find.byKey(Key('day-strip-${isoDate(today)}'))));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fake.moved, isEmpty);
    });

    testWidgets('téléphone : glisser une séance vers la gauche propose de la supprimer', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeSessions();
      await tester.pumpWidget(testApp(
        const WeekScreen(),
        overrides: clubOverrides(sessions: [session('s1', isoDate(today), 'À supprimer')], sessionActions: fake),
      ));
      await tester.pumpAndSettle();

      await tester.drag(find.text('À supprimer'), const Offset(-500, 0));
      await tester.pump();
      expect(find.text('Supprimer la séance ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
      await tester.pumpAndSettle();

      expect(fake.deleted, ['s1']);
    });

    testWidgets('téléphone : annuler la suppression garde la séance', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeSessions();
      await tester.pumpWidget(testApp(
        const WeekScreen(),
        overrides: clubOverrides(sessions: [session('s1', isoDate(today), 'Reste')], sessionActions: fake),
      ));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Reste'), const Offset(-500, 0));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
      await tester.pumpAndSettle();

      expect(fake.deleted, isEmpty);
      expect(find.text('Reste'), findsOneWidget);
    });

    testWidgets('vue mois : bouton bascule, affiche la grille et le mois courant', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(testApp(const WeekScreen(), overrides: clubOverrides()));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('day-strip-$dayA')), findsOneWidget);
      await tester.tap(find.byKey(const Key('toggle-month-view')));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('day-strip-$dayA')), findsNothing);
      expect(find.text(monthLabel(today)), findsOneWidget);
      expect(find.byKey(Key('month-day-${isoDate(today)}')), findsOneWidget);
    });

    testWidgets('vue mois : toucher un jour revient à l’agenda de ce jour', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sessions = [session('s1', dayB, 'Séance du mercredi')];
      await tester.pumpWidget(testApp(const WeekScreen(), overrides: clubOverrides(sessions: sessions)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toggle-month-view')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('month-day-$dayB')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle-month-view')), findsOneWidget); // on est bien revenu à la vue semaine
      expect(find.text('Séance du mercredi'), findsOneWidget);
    });

    testWidgets('tablette : un athlète ne peut ni ajouter ni déplacer', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final overrides = clubOverrides(
        me: membership(role: ClubRole.athlete),
        sessions: [session('s1', dayA, 'Séance')],
      );
      await tester.pumpWidget(testApp(const WeekScreen(), overrides: overrides));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('add-$dayA')), findsNothing);
      expect(find.byKey(const Key('drag-s1')), findsNothing);
      expect(find.text('Séance'), findsWidgets);
    });

    testWidgets('un athlète ouvre le détail avec le contenu des blocs', (tester) async {
      final blocks = {
        's1': const [
          SessionBlock(
            id: 'b1', sessionId: 's1', kind: BlockKind.main, position: 0, title: '', notes: '',
            items: [BlockItem(reps: 10, distanceM: 400, recoveryS: 60, intensity: '5k')],
          ),
          SessionBlock(
            id: 'b2', sessionId: 's1', kind: BlockKind.cooldown, position: 1, title: '', notes: '',
            items: [BlockItem(note: 'Footing 10\'')],
          ),
        ],
      };
      final overrides = clubOverrides(
        me: membership(role: ClubRole.athlete),
        sessions: [session('s1', todayIso, 'Ma séance')],
        blocks: blocks,
      );
      await tester.pumpWidget(testApp(const WeekScreen(), overrides: overrides));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ma séance'));
      await tester.pumpAndSettle();
      expect(find.text('Corps de séance'), findsOneWidget);
      expect(find.text("10 × 400 m · récup 1' · @5k"), findsOneWidget);
      expect(find.text('Retour au calme'), findsOneWidget);
      expect(find.text("Footing 10'"), findsOneWidget);
      expect(find.text('Volume d’effort : 4 km'), findsOneWidget);
      expect(find.byKey(const Key('session-save')), findsNothing, reason: 'lecture seule');
    });

    testWidgets('un coach qui touche une séance ouvre l’éditeur', (tester) async {
      tallScreen(tester, width: 400, height: 2600);
      await tester.pumpWidget(testApp(
        const WeekScreen(),
        overrides: clubOverrides(sessions: [session('s1', todayIso, 'Ouvre-moi')]),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ouvre-moi'));
      await tester.pumpAndSettle();
      expect(find.text('Modifier la séance'), findsOneWidget);
    });

    testWidgets('« + » propose nouvelle séance ou modèle', (tester) async {
      await tester.pumpWidget(testApp(const WeekScreen(), overrides: clubOverrides()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-session')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-blank')), findsOneWidget);
      expect(find.byKey(const Key('new-from-template')), findsOneWidget);

      await tester.tap(find.byKey(const Key('new-from-template')));
      await tester.pumpAndSettle();
      expect(find.textContaining('La bibliothèque est vide'), findsOneWidget);
    });
  });
}
