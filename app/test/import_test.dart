import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:coach/core/csv.dart';
import 'package:coach/core/notation.dart';
import 'package:coach/data/connector.dart';
import 'package:coach/data/import_csv.dart';
import 'package:coach/data/models.dart';

import 'helpers.dart';

const types = [
  fractionne,
  endurance,
  seuil,
  SessionType(id: 't-vit', name: 'Vitesse', color: Color(0xFF8E4EC6), icon: 'sprint'),
  SessionType(id: 't-vma', name: 'VMA', color: Color(0xFF000000), icon: 'run'),
];
const groups = [sprintGroup, demiGroup];

ImportResult run(String csv) => buildImport(csv, types: types, groups: groups);

void main() {
  group('lecture CSV', () {
    test('séparateur détecté : ; , ou tabulation', () {
      expect(parseCsv('a;b;c\n1;2;3'), [['a', 'b', 'c'], ['1', '2', '3']]);
      expect(parseCsv('a,b,c\n1,2,3'), [['a', 'b', 'c'], ['1', '2', '3']]);
      expect(parseCsv('a\tb\tc\n1\t2\t3'), [['a', 'b', 'c'], ['1', '2', '3']]);
    });

    test('champs entre guillemets : séparateur, guillemets doublés, retours à la ligne', () {
      final rows = parseCsv('t;c\n"a;b";"il dit ""oui"""\nx;"ligne 1\nligne 2"');
      expect(rows[1], ['a;b', 'il dit "oui"']);
      expect(rows[2], ['x', 'ligne 1\nligne 2']);
    });

    test('BOM, fins de ligne Windows, lignes vides, espaces autour des champs', () {
      final rows = parseCsv('﻿a;b\r\n 1 ; 2 \r\n\r\n;\r\n3;4\r\n');
      expect(rows, [['a', 'b'], ['1', '2'], ['3', '4']]);
    });

    test('un guillemet au milieu d’un champ reste un caractère (secondes : 30")', () {
      expect(parseCsv('t;c\n1;4x60 r30"')[1], ['1', '4x60 r30"']);
    });

    test('csvField échappe correctement', () {
      expect(csvField('simple'), 'simple');
      expect(csvField('a;b'), '"a;b"');
      expect(csvField('dit "oui"'), '"dit ""oui"""');
    });
  });

  group('dates et heures d’import', () {
    test('formats de date', () {
      expect(parseImportDate('2026-09-28'), '2026-09-28');
      expect(parseImportDate('28/09/2026'), '2026-09-28');
      expect(parseImportDate('28-09-2026'), '2026-09-28');
      expect(parseImportDate('28.09.26'), '2026-09-28');
      expect(parseImportDate('1/2/2026'), '2026-02-01');
    });

    test('dates impossibles refusées, pas décalées', () {
      expect(parseImportDate('31/02/2026'), isNull);
      expect(parseImportDate('2026-13-01'), isNull);
      expect(parseImportDate('demain'), isNull);
      expect(parseImportDate(''), isNull);
    });

    test('heures', () {
      expect(parseImportTime('18:30'), '18:30');
      expect(parseImportTime('18h30'), '18:30');
      expect(parseImportTime('18h'), '18:00');
      expect(parseImportTime('8:05'), '08:05');
      expect(parseImportTime('25:00'), isNull);
      expect(parseImportTime('18:75'), isNull);
    });

    test('normalizeKey', () {
      expect(normalizeKey('Retour au calme'), 'retouraucalme');
      expect(normalizeKey('Échauffement'), 'echauffement');
      expect(normalizeKey('durée_min'), 'dureemin');
    });
  });

  group('import de séances', () {
    test('le fichier modèle fourni est valide : 2 séances et 1 modèle', () {
      final r = buildImport(
        importTemplateCsv,
        types: types,
        groups: groups,
      );
      expect(r.fileError, isNull);
      expect(r.invalid.map((x) => x.error), isEmpty);
      expect(r.rows, hasLength(3));

      final d = r.rows[0].draft!;
      expect(d.isTemplate, isFalse);
      expect(d.date, '2026-09-28');
      expect(d.startTime, '18:30');
      expect(d.durationMin, 90);
      expect(d.groupIds, {'g-sprint', 'g-demi'});
      expect(d.typeId, 't-frac');
      expect(d.description, 'Piste couverte');
      expect(d.blocks.map((b) => b.kind.name), ['warmup', 'main', 'cooldown']);
      expect(d.blocks[0].items, [
        const BlockItem(note: "Footing 15'"),
        const BlockItem(reps: 4, distanceM: 60, recoveryS: 30),
      ]);
      expect(d.blocks[1].items, [
        const BlockItem(reps: 10, distanceM: 400, recoveryS: 60),
        const BlockItem(reps: 3, distanceM: 300, recoveryS: 60),
      ]);

      expect(r.rows[1].draft!.blocks.single.items, [const BlockItem(durationS: 3600, intensity: 'endurance')]);
      final tpl = r.rows[2].draft!;
      expect(tpl.isTemplate, isTrue);
      expect(tpl.groupIds, isEmpty);
      expect(tpl.date, isNull);
      expect(tpl.typeId, 't-seuil');
    });

    test('colonnes dans un autre ordre, accents et majuscules libres, séparateur virgule', () {
      final r = run('Titre,TYPE,Date,Groupes,Échauffement\nSéance,fractionné,28/09/2026,sprint,"Footing 15\'"');
      expect(r.fileError, isNull);
      final d = r.rows.single.draft!;
      expect(d.title, 'Séance');
      expect(d.typeId, 't-frac');
      expect(d.groupIds, {'g-sprint'});
      expect(d.blocks.single.kind, BlockKind.warmup);
    });

    test('un type se retrouve par préfixe non ambigu', () {
      expect(run('type;titre\nSeuil;A').rows.single.draft!.typeId, 't-seuil');
      // « V » est ambigu (Vitesse, VMA) → refusé plutôt que deviné.
      expect(run('type;titre\nV;A').rows.single.error, contains('type inconnu'));
    });

    test('retours par ligne, avec leur numéro (l’en-tête est la ligne 1)', () {
      final r = run('type;titre;date;groupes;heure;duree_min\n'
          'Fractionné;OK;2026-09-28;Sprint;;\n'
          ';Sans type;;;;\n'
          'Fractionné;;;;;\n'
          'Fractionné;Date;31/02/2026;Sprint;;\n'
          'Fractionné;Sans groupe;2026-09-28;;;\n'
          'Fractionné;Groupe;2026-09-28;Nul;;\n'
          'Fractionné;Heure;2026-09-28;Sprint;25h;\n'
          'Fractionné;Durée;2026-09-28;Sprint;;abc\n');
      expect(r.rows[0].isValid, isTrue);
      expect(r.rows[1].error, 'type manquant');
      expect(r.rows[2].error, 'titre manquant');
      expect(r.rows[3].error, contains('date illisible'));
      expect(r.rows[4].error, contains('groupe manquant'));
      expect(r.rows[5].error, contains('groupe inconnu « Nul »'));
      expect(r.rows[6].error, contains('heure illisible'));
      expect(r.rows[7].error, contains('durée illisible'));
      expect(r.rows.map((x) => x.line), [2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('erreurs de fichier', () {
      expect(run('').fileError, contains('vide'));
      expect(run('type;titre').fileError, contains('vide'));
      expect(run('a;b\n1;2').fileError, contains('type'));
      expect(run('type;a\nX;2').fileError, contains('titre'));
    });

    test('une séance sans date devient un modèle même si un groupe est indiqué', () {
      final d = run('type;titre;groupes\nFractionné;Modèle;Sprint').rows.single.draft!;
      expect(d.isTemplate, isTrue);
      expect(d.groupIds, isEmpty);
    });

    test('le contenu peut séparer les exercices par | ou par retour à la ligne', () {
      final r = run('type;titre;corps\nFractionné;A;"10x400 r1\'\n3x300 r1\'"\nFractionné;B;10x400 r1\' | 3x300 r1\'');
      for (final row in r.rows) {
        expect(row.draft!.blocks.single.items, hasLength(2));
      }
    });
  });

  group('connecteur : colonnes JSON', () {
    test('items est décodé avant l’envoi (sinon Postgres reçoit une chaîne, pas un tableau)', () {
      final row = decodeJsonColumns('session_blocks', {
        'id': 'b1',
        'items': '[{"reps":10,"distance_m":400}]',
        'title': 'Corps',
      });
      expect(row['items'], isA<List<dynamic>>());
      expect((row['items'] as List).single, {'reps': 10, 'distance_m': 400});
      expect(row['title'], 'Corps', reason: 'les autres colonnes ne bougent pas');
    });

    test('valeurs déjà décodées ou nulles, autres tables : inchangées', () {
      expect(decodeJsonColumns('session_blocks', {'items': null})['items'], isNull);
      expect(decodeJsonColumns('session_blocks', {'id': 'x'}), {'id': 'x'});
      final other = {'items': 'texte'};
      expect(decodeJsonColumns('sessions', other), other);
    });
  });

  group('blocs : lecture de la colonne items', () {
    test('valeur corrompue ou absente : liste vide, sans exception', () {
      expect(decodeItems(null), isEmpty);
      expect(decodeItems('pas du json'), isEmpty);
      expect(decodeItems('{"a":1}'), isEmpty);
      expect(decodeItems('[]'), isEmpty);
    });

    test('aller-retour encodeItems / decodeItems', () {
      const items = [BlockItem(reps: 10, distanceM: 400, recoveryS: 60), BlockItem(note: 'Gammes')];
      expect(decodeItems(encodeItems(items)), items);
    });

    test('SessionBlock.fromRow', () {
      final b = SessionBlock.fromRow({
        'id': 'b', 'session_id': 's', 'kind': 'cooldown', 'position': 2, 'title': '', 'notes': '',
        'items': encodeItems(const [BlockItem(durationS: 600)]),
      });
      expect(b.kind, BlockKind.cooldown);
      expect(b.heading, 'Retour au calme');
      expect(b.items.single.durationS, 600);
      expect(BlockKind.parse('n_importe_quoi'), BlockKind.other);
    });
  });
}
