import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:coach/core/errors.dart';
import 'package:coach/core/format.dart';
import 'package:coach/data/actions.dart';
import 'package:coach/data/database.dart';
import 'package:coach/data/models.dart';
import 'package:coach/data/queries.dart';
import 'package:coach/router.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('dates', () {
    test('mondayOf renvoie le lundi de la semaine', () {
      expect(isoDate(mondayOf(DateTime(2026, 9, 21))), '2026-09-21'); // lundi
      expect(isoDate(mondayOf(DateTime(2026, 9, 24))), '2026-09-21'); // jeudi
      expect(isoDate(mondayOf(DateTime(2026, 9, 27))), '2026-09-21'); // dimanche
      expect(isoDate(mondayOf(DateTime(2026, 1, 1))), '2025-12-29'); // à cheval sur l'année
    });

    test('addDays traverse le changement d’heure sans décalage', () {
      // Passage à l'heure d'hiver 2026 : dimanche 25 octobre.
      expect(isoDate(addDays(DateTime(2026, 10, 24), 1)), '2026-10-25');
      expect(isoDate(addDays(DateTime(2026, 10, 24), 2)), '2026-10-26');
      expect(isoDate(addDays(DateTime(2026, 3, 28), 2)), '2026-03-30');
    });

    test('libellés de semaine', () {
      expect(weekRangeLabel(DateTime(2026, 9, 14)), '14 – 20 sept.');
      expect(weekRangeLabel(DateTime(2026, 9, 28)), '28 sept. – 4 oct.');
      expect(longDayLabel(DateTime(2026, 9, 24)), 'Jeudi 24 septembre');
    });

    test('parseIsoDate et shortTime', () {
      expect(parseIsoDate('2026-09-24'), DateTime(2026, 9, 24));
      expect(shortTime('18:30:00'), '18:30');
      expect(shortTime('18:30'), '18:30');
    });
  });

  group('invitations et erreurs', () {
    test('formatInviteCode', () {
      expect(formatInviteCode('abcdef123456'), 'ABCD-EF12-3456');
      expect(formatInviteCode('court'), 'COURT');
    });

    test('les codes serveur sont traduits', () {
      expect(humanError(const PostgrestException(message: 'club_name_taken')), 'Ce nom de club est déjà pris.');
      expect(humanError(const PostgrestException(message: 'invitation_invalid')), contains('expiré'));
      expect(humanError(const PostgrestException(message: 'inconnu_xyz')), contains('inconnu_xyz'));
      expect(humanError(const AuthException('Invalid login credentials')), 'Email ou mot de passe incorrect.');
    });
  });

  group('AppPhase (routage)', () {
    ProviderContainer container({
      User? user = testUser,
      Stream<List<Membership>>? memberships,
      bool synced = false,
    }) {
      final c = ProviderContainer(overrides: [
        userProvider.overrideWithValue(user),
        myMembershipsProvider.overrideWith((ref) => memberships ?? Stream.value(const [])),
        hasSyncedProvider.overrideWith((ref) => Stream.value(synced)),
      ]);
      addTearDown(c.dispose);
      // Riverpod 3 met en pause un provider sans auditeur : comme dans l'app (où les widgets
      // écoutent), on garde une écoute active pour que les flux avancent.
      c.listen(appPhaseProvider, (_, _) {});
      c.listen(myMembershipsProvider, (_, _) {});
      c.listen(hasSyncedProvider, (_, _) {});
      return c;
    }

    Future<AppPhase> phase(ProviderContainer c) async {
      await pumpEventQueue();
      return c.read(appPhaseProvider);
    }

    test('déconnecté', () async {
      expect(await phase(container(user: null)), AppPhase.signedOut);
    });

    test('nouvel appareil : liste vide mais pas encore synchronisé → on attend', () async {
      expect(await phase(container(synced: false)), AppPhase.syncing);
    });

    test('première synchro terminée et aucun club → onboarding', () async {
      expect(await phase(container(synced: true)), AppPhase.noClub);
    });

    test('demande en attente', () async {
      final c = container(memberships: Stream.value([membership(active: false, role: ClubRole.athlete)]));
      expect(await phase(c), AppPhase.pending);
    });

    test('membre actif → accueil, même avant la fin de la synchro', () async {
      final c = container(memberships: Stream.value([membership()]));
      expect(await phase(c), AppPhase.ready);
    });

    test('adhésions encore en chargement → on attend', () {
      final c = container(memberships: const Stream.empty());
      expect(c.read(appPhaseProvider), AppPhase.syncing);
    });

    test('un membre actif prime sur une demande en attente ailleurs', () async {
      final c = container(memberships: Stream.value([
        membership(id: 'm1', clubId: 'a', active: false, role: ClubRole.athlete),
        membership(id: 'm2', clubId: 'b'),
      ]));
      await phase(c);
      expect(c.read(appPhaseProvider), AppPhase.ready);
      expect(c.read(clubIdProvider), 'b');
    });
  });

  group('modèles', () {
    test('Membership.fromRow', () {
      final m = Membership.fromRow({
        'id': 'm', 'club_id': 'c', 'user_id': 'u', 'role': 'owner', 'status': 'active', 'display_name': 'Julie',
      });
      expect(m.role, ClubRole.owner);
      expect(m.isActive, isTrue);
      expect(m.role.isCoach, isTrue);
      expect(ClubRole.athlete.isCoach, isFalse);
    });

    test('PlannedSession.fromRow accepte les champs optionnels absents', () {
      final s = PlannedSession.fromRow({
        'id': 's', 'type_id': 't', 'title': '6x400', 'group_id': 'g', 'scheduled_date': '2026-09-24',
        'start_time': null, 'duration_min': null, 'description': null,
      });
      expect(s.startTime, isNull);
      expect(s.durationMin, isNull);
      expect(s.description, '');
    });

    test('SessionType.fromRow lit la couleur hexadécimale', () {
      final t = SessionType.fromRow({'id': 't', 'name': 'Vitesse', 'color': '#8E4EC6', 'icon': 'sprint'});
      expect(t.color.toARGB32(), 0xFF8E4EC6);
    });
  });
}
