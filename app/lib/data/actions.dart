import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'models.dart';

const _uuid = Uuid();

/// `ABCDEF123456` → `ABCD-EF12-3456`
String formatInviteCode(String code) {
  final c = code.toUpperCase();
  if (c.length != 12) return c;
  return '${c.substring(0, 4)}-${c.substring(4, 8)}-${c.substring(8)}';
}

class InvitationPreview {
  const InvitationPreview({
    required this.clubName,
    required this.role,
    required this.valid,
  });
  final String clubName;
  final ClubRole role;
  final bool valid;
}

/// Opérations d'administration du club. Elles passent par des fonctions serveur (RPC) qui
/// vérifient les droits : elles exigent d'être en ligne, contrairement à la planification.
class ClubActions {
  ClubActions(this._client);
  final SupabaseClient _client;

  Future<String> createClub(String name) async =>
      await _client.rpc('create_club', params: {'p_name': name}) as String;

  /// Recherche « live » : sous-chaîne, insensible à la casse, jusqu'à 20 clubs (voir la
  /// migration `search_clubs` — moins de 2 caractères renvoie toujours une liste vide).
  Future<List<Club>> searchClubs(String query) async {
    final rows = await _client.rpc('search_clubs', params: {'p_query': query}) as List<dynamic>;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        Club(id: r['id'] as String, name: r['name'] as String),
    ];
  }

  Future<void> requestJoin(String clubId, ClubRole role) =>
      _client.rpc('request_join', params: {'p_club': clubId, 'p_role': role.name});

  Future<InvitationPreview?> previewInvitation(String code) async {
    final rows = await _client.rpc('preview_invitation', params: {'p_code': code}) as List<dynamic>;
    if (rows.isEmpty) return null;
    final r = rows.first as Map<String, dynamic>;
    return InvitationPreview(
      clubName: r['club_name'] as String,
      role: ClubRole.parse(r['role'] as String),
      valid: r['valid'] as bool,
    );
  }

  Future<void> acceptInvitation(String code) =>
      _client.rpc('accept_invitation', params: {'p_code': code});

  Future<void> approve(String membershipId) =>
      _client.rpc('approve_membership', params: {'p_membership': membershipId});

  Future<void> reject(String membershipId) =>
      _client.rpc('reject_membership', params: {'p_membership': membershipId});

  /// `maxUses` null = code réutilisable.
  Future<String> createInvitation(
    String clubId,
    ClubRole role, {
    String? athleteId,
    int? maxUses = 1,
  }) async =>
      await _client.rpc('create_invitation', params: {
        'p_club': clubId,
        'p_role': role.name,
        'p_athlete': athleteId,
        'p_max_uses': maxUses,
      }) as String;

  Future<void> transferOwnership(String clubId, String newOwnerUserId) => _client.rpc(
        'transfer_ownership',
        params: {'p_club': clubId, 'p_new_owner': newOwnerUserId},
      );

  Future<void> leaveClub(String clubId) => _client.rpc('leave_club', params: {'p_club': clubId});

  Future<void> removeMember(String clubId, String userId) =>
      _client.rpc('remove_member', params: {'p_club': clubId, 'p_user': userId});
}

/// Écritures de planification : elles vont dans la base locale, donc fonctionnent hors ligne.
/// PowerSync les met en file et les envoie au serveur dès que le réseau revient.
class PlanningActions {
  PlanningActions(this._db);
  final PowerSyncDatabase _db;

  Future<void> addGroup(String clubId, String name) => _db.execute(
        'INSERT INTO training_groups (id, club_id, name, sort_order, archived) '
        'VALUES (?, ?, ?, 0, 0)',
        [_uuid.v4(), clubId, name.trim()],
      );

  Future<void> archiveGroup(String groupId) =>
      _db.execute('UPDATE training_groups SET archived = 1 WHERE id = ?', [groupId]);

  Future<String> addAthlete(String clubId, String fullName) async {
    final id = _uuid.v4();
    await _db.execute(
      'INSERT INTO athletes (id, club_id, full_name) VALUES (?, ?, ?)',
      [id, clubId, fullName.trim()],
    );
    return id;
  }

  Future<void> setGroupMembership({
    required String clubId,
    required Athlete athlete,
    required String groupId,
    required bool member,
  }) async {
    if (member) {
      await _db.execute(
        'INSERT INTO group_athletes (id, club_id, group_id, athlete_id, user_id) '
        'VALUES (?, ?, ?, ?, ?)',
        [_uuid.v4(), clubId, groupId, athlete.id, athlete.userId],
      );
    } else {
      await _db.execute(
        'DELETE FROM group_athletes WHERE group_id = ? AND athlete_id = ?',
        [groupId, athlete.id],
      );
    }
  }

  /// Présence à l'entraînement, prise par un coach (voir `attendances`).
  Future<void> setAttendance({
    required String clubId,
    required String groupId,
    required String athleteId,
    required String date,
    required bool present,
  }) async {
    if (present) {
      await _db.execute(
        'INSERT INTO attendances (id, club_id, group_id, athlete_id, date) VALUES (?, ?, ?, ?, ?)',
        [_uuid.v4(), clubId, groupId, athleteId, date],
      );
    } else {
      await _db.execute(
        'DELETE FROM attendances WHERE group_id = ? AND athlete_id = ? AND date = ?',
        [groupId, athleteId, date],
      );
    }
  }
}

class AccountActions {
  AccountActions(this._client, this._db);
  final SupabaseClient _client;
  final PowerSyncDatabase _db;

  /// Vrai s'il reste des modifications locales pas encore envoyées au serveur.
  Future<bool> hasPendingUploads() async => await _db.getNextCrudTransaction() != null;

  /// La déconnexion vide la base locale (voir syncLifecycleProvider) : à n'appeler qu'après
  /// avoir prévenu l'utilisateur si `hasPendingUploads`.
  Future<void> signOut() => _client.auth.signOut();

  /// Supprime définitivement le compte (RPC `delete_own_account`) : rejeté avec
  /// `owner_must_transfer` tant qu'on est propriétaire actif d'un club. Se déconnecte ensuite
  /// (la session serveur n'est plus valide, mais l'état local doit suivre).
  Future<void> deleteAccount() async {
    await _client.rpc('delete_own_account');
    await _client.auth.signOut();
  }
}

final clubActionsProvider = Provider<ClubActions>((ref) => ClubActions(ref.watch(supabaseProvider)));

final planningActionsProvider = Provider<PlanningActions>(
  (ref) => PlanningActions(ref.watch(powerSyncProvider)),
);

final accountActionsProvider = Provider<AccountActions>(
  (ref) => AccountActions(ref.watch(supabaseProvider), ref.watch(powerSyncProvider)),
);
