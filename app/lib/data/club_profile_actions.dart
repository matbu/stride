import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, SupabaseClient;

import 'database.dart';

/// Profil libre-service du club (description, logo) — même principe que `ProfileActions` pour
/// un athlète : tout passe par la base locale, sauf le logo, qui passe par Supabase Storage (pas
/// synchronisé par PowerSync, donc son envoi exige d'être en ligne).
class ClubProfileActions {
  ClubProfileActions(this._client, this._db);
  final SupabaseClient _client;
  final PowerSyncDatabase _db;

  Future<void> saveDescription({required String clubId, required String description}) => _db.execute(
        'INSERT INTO club_profiles (id, description) VALUES (?, ?) '
        'ON CONFLICT(id) DO UPDATE SET description = excluded.description',
        [clubId, description.trim()],
      );

  /// Envoie le logo vers Supabase Storage puis enregistre son chemin (qui, lui, se synchronise
  /// normalement ensuite). `ext` sans le point, ex. `png`.
  Future<void> uploadLogo({required String clubId, required Uint8List bytes, required String ext}) async {
    final path = '$clubId/logo.$ext';
    // TEMPORAIRE (débogage upload) : à retirer une fois le problème RLS résolu.
    final auth = _client.storage.headers['Authorization'] ?? '<absent>';
    debugPrint(
      '[upload-debug] uid=${_client.auth.currentUser?.id} '
      'session=${_client.auth.currentSession != null} '
      'expired=${_client.auth.currentSession?.isExpired} '
      'storageAuthHeader=${auth.substring(0, auth.length < 24 ? auth.length : 24)}…',
    );
    await _client.storage.from('club_logos').uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
    await _db.execute(
      'INSERT INTO club_profiles (id, logo_path) VALUES (?, ?) '
      'ON CONFLICT(id) DO UPDATE SET logo_path = excluded.logo_path',
      [clubId, path],
    );
  }

  String logoUrl(String path) => _client.storage.from('club_logos').getPublicUrl(path);
}

final clubProfileActionsProvider = Provider<ClubProfileActions>(
  (ref) => ClubProfileActions(ref.watch(supabaseProvider), ref.watch(powerSyncProvider)),
);
