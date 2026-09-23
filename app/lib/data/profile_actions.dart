import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, SupabaseClient;
import 'package:uuid/uuid.dart';

import 'database.dart';

const _uuid = Uuid();

/// Profil libre-service d'un athlète (photo, bio, lien FFA, records personnels). Tout passe par
/// la base locale, sauf la photo : Supabase Storage n'est pas synchronisé par PowerSync, donc son
/// envoi exige d'être en ligne (comme les opérations d'administration du club).
class ProfileActions {
  ProfileActions(this._client, this._db);
  final SupabaseClient _client;
  final PowerSyncDatabase _db;

  Future<void> saveProfile({required String athleteId, required String clubId, String? bio, String? ffaUrl}) async {
    final trimmedUrl = ffaUrl?.trim();
    final ffa = (trimmedUrl == null || trimmedUrl.isEmpty) ? null : trimmedUrl;
    if (await _hasProfile(athleteId)) {
      await _db.execute(
        'UPDATE athlete_profiles SET bio = ?, ffa_url = ? WHERE id = ?',
        [bio?.trim() ?? '', ffa, athleteId],
      );
    } else {
      await _db.execute(
        'INSERT INTO athlete_profiles (id, club_id, bio, ffa_url) VALUES (?, ?, ?, ?)',
        [athleteId, clubId, bio?.trim() ?? '', ffa],
      );
    }
  }

  /// Envoie la photo vers Supabase Storage puis enregistre son chemin (qui, lui, se synchronise
  /// normalement ensuite). `ext` sans le point, ex. `jpg`.
  Future<void> uploadAvatar({
    required String athleteId,
    required String clubId,
    required Uint8List bytes,
    required String ext,
  }) async {
    final uid = _client.auth.currentUser!.id;
    final path = '$uid/avatar.$ext';
    await _client.storage.from('avatars').uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
    if (await _hasProfile(athleteId)) {
      await _db.execute('UPDATE athlete_profiles SET avatar_path = ? WHERE id = ?', [path, athleteId]);
    } else {
      await _db.execute(
        'INSERT INTO athlete_profiles (id, club_id, avatar_path) VALUES (?, ?, ?)',
        [athleteId, clubId, path],
      );
    }
  }

  /// La base locale expose chaque table comme une vue (PowerSync) : SQLite refuse l'upsert
  /// (`ON CONFLICT ... DO UPDATE`) dessus (« cannot UPSERT a view ») — il faut vérifier
  /// l'existence de la ligne nous-mêmes puis choisir INSERT ou UPDATE.
  Future<bool> _hasProfile(String athleteId) async =>
      (await _db.getAll('SELECT 1 FROM athlete_profiles WHERE id = ?', [athleteId])).isNotEmpty;

  String avatarUrl(String path) => _client.storage.from('avatars').getPublicUrl(path);

  Future<void> saveRecord({
    String? id,
    required String athleteId,
    required String clubId,
    required String discipline,
    required String performance,
    String? achievedOn,
    String? competition,
  }) {
    if (id != null) {
      return _db.execute(
        'UPDATE athlete_records SET discipline = ?, performance = ?, achieved_on = ?, competition = ? '
        'WHERE id = ?',
        [discipline.trim(), performance.trim(), achievedOn, competition?.trim() ?? '', id],
      );
    }
    return _db.execute(
      'INSERT INTO athlete_records (id, athlete_id, club_id, discipline, performance, achieved_on, competition) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [_uuid.v4(), athleteId, clubId, discipline.trim(), performance.trim(), achievedOn, competition?.trim() ?? ''],
    );
  }

  Future<void> deleteRecord(String id) => _db.execute('DELETE FROM athlete_records WHERE id = ?', [id]);
}

final profileActionsProvider = Provider<ProfileActions>(
  (ref) => ProfileActions(ref.watch(supabaseProvider), ref.watch(powerSyncProvider)),
);
