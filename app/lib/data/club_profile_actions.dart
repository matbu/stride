import 'dart:typed_data';

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

  Future<void> saveDescription({required String clubId, required String description}) async {
    if (await _hasProfile(clubId)) {
      await _db.execute('UPDATE club_profiles SET description = ? WHERE id = ?', [description.trim(), clubId]);
    } else {
      await _db.execute('INSERT INTO club_profiles (id, description) VALUES (?, ?)', [clubId, description.trim()]);
    }
  }

  /// Envoie le logo vers Supabase Storage puis enregistre son chemin (qui, lui, se synchronise
  /// normalement ensuite). `ext` sans le point, ex. `png`. Le chemin inclut un horodatage : un
  /// remplacement au même chemin garderait la même URL publique, et l'image resterait affichée
  /// depuis le cache réseau de Flutter même après un nouvel envoi.
  Future<void> uploadLogo({required String clubId, required Uint8List bytes, required String ext}) async {
    final existing = await _db.getAll('SELECT logo_path FROM club_profiles WHERE id = ?', [clubId]);
    final oldPath = existing.isEmpty ? null : existing.first['logo_path'] as String?;
    final path = '$clubId/logo_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('club_logos').uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
    if (existing.isEmpty) {
      await _db.execute('INSERT INTO club_profiles (id, logo_path) VALUES (?, ?)', [clubId, path]);
    } else {
      await _db.execute('UPDATE club_profiles SET logo_path = ? WHERE id = ?', [path, clubId]);
    }
    if (oldPath != null) {
      try {
        await _client.storage.from('club_logos').remove([oldPath]);
      } catch (_) {
        // Best effort : un fichier orphelin ne gêne pas, l'important est le nouveau logo.
      }
    }
  }

  String logoUrl(String path) => _client.storage.from('club_logos').getPublicUrl(path);

  /// La base locale expose chaque table comme une vue (PowerSync) : SQLite refuse l'upsert
  /// (`ON CONFLICT ... DO UPDATE`) dessus (« cannot UPSERT a view ») — il faut vérifier
  /// l'existence de la ligne nous-mêmes puis choisir INSERT ou UPDATE.
  Future<bool> _hasProfile(String clubId) async =>
      (await _db.getAll('SELECT 1 FROM club_profiles WHERE id = ?', [clubId])).isNotEmpty;
}

final clubProfileActionsProvider = Provider<ClubProfileActions>(
  (ref) => ClubProfileActions(ref.watch(supabaseProvider), ref.watch(powerSyncProvider)),
);
