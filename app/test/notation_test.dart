import 'package:flutter_test/flutter_test.dart';

import 'package:coach/core/notation.dart';

BlockItem one(String s) {
  final items = parseNotation(s);
  expect(items, hasLength(1), reason: '« $s » → $items');
  return items.single;
}

void main() {
  group('saisie rapide', () {
    test('les exemples de la demande : deux exercices sur une ligne', () {
      final items = parseNotation("10x400 r1' 3x300 r1'");
      expect(items, [
        const BlockItem(reps: 10, distanceM: 400, recoveryS: 60),
        const BlockItem(reps: 3, distanceM: 300, recoveryS: 60),
      ]);
    });

    test('répétitions, distance, récupération', () {
      expect(one("10x400 r1'"), const BlockItem(reps: 10, distanceM: 400, recoveryS: 60));
      expect(one("6x400 r1'30"), const BlockItem(reps: 6, distanceM: 400, recoveryS: 90));
      expect(one('8 x 200 r 45"'), const BlockItem(reps: 8, distanceM: 200, recoveryS: 45));
      expect(one('10×400 r90'), const BlockItem(reps: 10, distanceM: 400, recoveryS: 90),
          reason: 'signe × et récup nue en secondes');
      expect(one('10X400R1\''), const BlockItem(reps: 10, distanceM: 400, recoveryS: 60),
          reason: 'majuscules, sans espaces');
      expect(one("10x400 récup 1'30"), const BlockItem(reps: 10, distanceM: 400, recoveryS: 90));
      expect(one('10x400 recup 30s'), const BlockItem(reps: 10, distanceM: 400, recoveryS: 30));
    });

    test('distances : mètres, kilomètres, sans répétition', () {
      expect(one('4x2km'), const BlockItem(reps: 4, distanceM: 2000));
      expect(one('3 x 1,5 km'), const BlockItem(reps: 3, distanceM: 1500));
      expect(one('5x200m'), const BlockItem(reps: 5, distanceM: 200));
      expect(one('5x60 m'), const BlockItem(reps: 5, distanceM: 60));
      expect(one('1500'), const BlockItem(distanceM: 1500));
      expect(one('10km'), const BlockItem(distanceM: 10000));
    });

    test('efforts en durée', () {
      expect(one("6x3' r1'"), const BlockItem(reps: 6, durationS: 180, recoveryS: 60));
      expect(one("6x1'30 r45\""), const BlockItem(reps: 6, durationS: 90, recoveryS: 45));
      expect(one('8x30" r30"'), const BlockItem(reps: 8, durationS: 30, recoveryS: 30));
      expect(one('10x45s r15s'), const BlockItem(reps: 10, durationS: 45, recoveryS: 15));
      expect(one('20 min'), const BlockItem(durationS: 1200));
      expect(one('1h'), const BlockItem(durationS: 3600));
      expect(one('1h30'), const BlockItem(durationS: 5400));
      expect(one("30''"), const BlockItem(durationS: 30), reason: 'deux apostrophes = secondes');
      expect(one("2x10' r2'"), const BlockItem(reps: 2, durationS: 600, recoveryS: 120));
    });

    test('récupération en distance', () {
      expect(one('5x200 r200m'), const BlockItem(reps: 5, distanceM: 200, recoveryM: 200));
      expect(one('4x1km r400m'), const BlockItem(reps: 4, distanceM: 1000, recoveryM: 400));
    });

    test('intensité, dans les deux ordres', () {
      expect(one("4x2km @10k r2'"), const BlockItem(reps: 4, distanceM: 2000, recoveryS: 120, intensity: '10k'));
      expect(one("4x2km r2' @10k"), const BlockItem(reps: 4, distanceM: 2000, recoveryS: 120, intensity: '10k'));
      expect(one('6x400 @95% VMA').intensity, '95% VMA');
      expect(one('6x400 allure 5k').intensity, '5k');
      expect(one('20 min @endurance').intensity, 'endurance');
    });

    test('plusieurs exercices : sur une ligne, en lignes, avec ;', () {
      const expected = [
        BlockItem(reps: 10, distanceM: 400, recoveryS: 60),
        BlockItem(reps: 3, distanceM: 300, recoveryS: 60),
      ];
      expect(parseNotation("10x400 r1' 3x300 r1'"), expected);
      expect(parseNotation("10x400 r1'\n3x300 r1'"), expected);
      expect(parseNotation("10x400 r1'; 3x300 r1'"), expected);
      expect(parseNotation("10x400 r1'\n\n  3x300 r1'  \n"), expected);
      expect(parseNotation("10x400 r1'3x300 r1'"), expected, reason: 'sans espace entre les deux');
    });

    test('texte libre conservé comme note', () {
      expect(one('Footing en côte'), const BlockItem(note: 'Footing en côte'));
      expect(one("Footing 45' + gammes"), const BlockItem(note: "Footing 45' + gammes"));
      expect(one('2 séries de gammes'), const BlockItem(note: '2 séries de gammes'),
          reason: '« 2 » n’est pas une distance');
      expect(one('rapide et relâché'), const BlockItem(note: 'rapide et relâché'),
          reason: '« r » d’un mot n’est pas une récupération');
      expect(one("10x400 r1' en côte"), const BlockItem(reps: 10, distanceM: 400, recoveryS: 60, note: 'en côte'));
      expect(one("45' footing"), const BlockItem(durationS: 2700, note: 'footing'));
    });

    test('la note suit l’exercice qui précède', () {
      final items = parseNotation("10x400 r1' en côte 3x300 r1' à fond");
      expect(items, [
        const BlockItem(reps: 10, distanceM: 400, recoveryS: 60, note: 'en côte'),
        const BlockItem(reps: 3, distanceM: 300, recoveryS: 60, note: 'à fond'),
      ]);
    });

    test('entrées vides ou absurdes ne plantent pas', () {
      expect(parseNotation(''), isEmpty);
      expect(parseNotation('   \n ; '), isEmpty);
      expect(parseNotation('0x400'), isNotEmpty, reason: 'gardé comme texte');
      expect(() => parseNotation('x x x 12 12x'), returnsNormally);
      expect(() => parseNotation("99999999999999x400 r1'"), returnsNormally);
    });
  });

  group('aller-retour notation ⇄ exercice', () {
    const samples = [
      BlockItem(reps: 10, distanceM: 400, recoveryS: 60),
      BlockItem(reps: 6, distanceM: 400, recoveryS: 90, intensity: '5k'),
      BlockItem(reps: 4, distanceM: 2000, recoveryS: 120),
      BlockItem(reps: 3, distanceM: 1500),
      BlockItem(reps: 5, distanceM: 200, recoveryM: 200),
      BlockItem(reps: 5, distanceM: 20, recoveryS: 90),
      BlockItem(reps: 8, durationS: 30, recoveryS: 30),
      BlockItem(reps: 2, durationS: 600, recoveryS: 120),
      BlockItem(durationS: 3600),
      BlockItem(durationS: 5400, intensity: 'endurance'),
      BlockItem(durationS: 3690),
      BlockItem(distanceM: 1250),
      BlockItem(reps: 10, distanceM: 400, recoveryS: 60, note: 'en côte'),
      BlockItem(note: 'Gammes éducatives'),
    ];

    for (final item in samples) {
      test(item.toNotation(), () {
        expect(parseNotation(item.toNotation()), [item]);
      });
    }

    test('JSON', () {
      for (final item in samples) {
        expect(BlockItem.fromJson(item.toJson()), item);
      }
      expect(const BlockItem(reps: 3, distanceM: 300, recoveryS: 60).toJson(),
          {'reps': 3, 'distance_m': 300, 'recovery_s': 60});
    });
  });

  group('affichage', () {
    test('forme lisible', () {
      expect(const BlockItem(reps: 10, distanceM: 400, recoveryS: 60).format(), "10 × 400 m · récup 1'");
      expect(const BlockItem(reps: 3, distanceM: 1500, recoveryS: 90, intensity: '10k').format(),
          "3 × 1,5 km · récup 1'30 · @10k");
      expect(const BlockItem(durationS: 3600).format(), '1h');
      expect(const BlockItem(reps: 5, distanceM: 200, recoveryM: 200).format(), '5 × 200 m · récup 200 m');
      expect(const BlockItem(note: 'Gammes').format(), 'Gammes');
    });

    test('formatDuration', () {
      expect(formatDuration(30), '30"');
      expect(formatDuration(60), "1'");
      expect(formatDuration(90), "1'30");
      expect(formatDuration(3600), '1h');
      expect(formatDuration(5400), '1h30');
      expect(formatDuration(3690), "61'30");
    });

    test('volume', () {
      final items = parseNotation("10x400 r1' 3x300 r1'\n20 min");
      expect(totalVolumeM(items), 10 * 400 + 3 * 300);
      expect(formatDistance(4900), '4,9 km');
      expect(formatDistance(5000), '5 km');
      expect(formatDistance(800), '800 m');
    });
  });
}
