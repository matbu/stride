import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, SupabaseClient;
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'models.dart';

const _uuid = Uuid();
const _bucket = 'resources';

/// Taille maximale d'un média, alignée sur `file_size_limit` du bucket (voir la migration
/// `resources`) : vérifiée avant l'envoi pour un message clair plutôt qu'un refus du serveur.
const maxResourceFileBytes = 20 * 1024 * 1024;

/// Ressources du club. Les liens passent par la base locale (hors ligne possible) ; les médias
/// et les ressources publiques exigent le réseau : envoi vers Storage, ou lecture/écriture de
/// lignes d'autres clubs, qui ne sont pas synchronisées.
class ResourceActions {
  ResourceActions(this._client, this._db, this._userId);
  final SupabaseClient _client;
  final PowerSyncDatabase _db;
  final String? Function() _userId;

  Future<void> addLink({
    required String clubId,
    required String url,
    required String title,
    String description = '',
    required bool isPublic,
  }) {
    final uri = Uri.parse(url);
    return _insert(
      clubId: clubId,
      kind: ResourceKind.ofUrl(uri),
      title: title,
      description: description,
      url: uri.toString(),
      isPublic: isPublic,
    );
  }

  /// Envoie le média vers Storage puis crée la ressource. `ext` sans le point, ex. `mp4`.
  Future<void> addFile({
    required String clubId,
    required ResourceKind kind,
    required Uint8List bytes,
    required String ext,
    required String title,
    String description = '',
    required bool isPublic,
  }) async {
    if (bytes.length > maxResourceFileBytes) throw const ResourceTooLarge();
    final path = '$clubId/${_uuid.v4()}.${ext.toLowerCase()}';
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _contentType(kind, ext)),
        );
    await _insert(
      clubId: clubId,
      kind: kind,
      title: title,
      description: description,
      storagePath: path,
      isPublic: isPublic,
    );
  }

  Future<void> _insert({
    required String clubId,
    required ResourceKind kind,
    required String title,
    required String description,
    String? url,
    String? storagePath,
    required bool isPublic,
  }) =>
      _db.execute(
        'INSERT INTO resources (id, club_id, kind, title, description, url, storage_path, visibility, '
        'created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          _uuid.v4(), clubId, kind.name, title.trim(), description.trim(), url, storagePath,
          isPublic ? 'public' : 'club', _userId(),
        ],
      );

  /// Modifie une ressource du club (pas une référence : son contenu suit l'originale).
  Future<void> update(Resource r, {required String title, required String description, required bool isPublic}) =>
      _db.execute(
        'UPDATE resources SET title = ?, description = ?, visibility = ? WHERE id = ?',
        [title.trim(), description.trim(), isPublic ? 'public' : 'club', r.id],
      );

  /// Supprime la ressource, et son fichier s'il appartient au club (celui d'une référence est
  /// celui de l'autre club). Le fichier part au mieux : hors ligne, il reste orphelin.
  Future<void> delete(Resource r) async {
    await _db.execute('DELETE FROM resources WHERE id = ?', [r.id]);
    if (r.isReference || r.storagePath == null) return;
    try {
      await _client.storage.from(_bucket).remove([r.storagePath!]);
    } catch (_) {
      // Best effort : un fichier orphelin ne gêne pas l'utilisateur.
    }
  }

  /// Ressources publiques des autres clubs (originales uniquement), les plus récentes d'abord.
  Future<List<Resource>> browsePublic({required String clubId, String search = ''}) async {
    var query = _client
        .from('resources')
        .select()
        .eq('visibility', 'public')
        .isFilter('source_id', null)
        .neq('club_id', clubId);
    final term = search.trim();
    if (term.isNotEmpty) {
      final escaped = term.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
      query = query.ilike('title', '%$escaped%');
    }
    final rows = await query.order('created_at', ascending: false).limit(100);
    return [for (final r in rows) Resource.fromRow(r)];
  }

  /// Ressource publique d'un autre club ayant exactement ce lien, pour proposer de l'ajouter
  /// plutôt que d'en créer une nouvelle. Null si aucune, ou hors ligne.
  Future<Resource?> findPublicByUrl({required String clubId, required String url}) async {
    try {
      final rows = await _client
          .from('resources')
          .select()
          .eq('visibility', 'public')
          .isFilter('source_id', null)
          .neq('club_id', clubId)
          .eq('url', url)
          .limit(1);
      return rows.isEmpty ? null : Resource.fromRow(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// Ajoute une ressource publique d'un autre club à son club, par référence. Écrit directement
  /// sur le serveur (et non en local) : le refus éventuel (plus publique entre-temps) s'affiche
  /// tout de suite ; la ligne revient ensuite par la synchronisation.
  Future<void> addPublic({required String clubId, required Resource source}) async {
    final already = await _db.getAll(
      'SELECT 1 FROM resources WHERE club_id = ? AND source_id = ?',
      [clubId, source.id],
    );
    if (already.isNotEmpty) return;
    await _client.from('resources').insert({
      'club_id': clubId,
      'source_id': source.id,
      // Recopiés par le serveur ; envoyés quand même pour satisfaire les contraintes.
      'kind': source.kind.name,
      'title': source.title,
      'url': source.url,
      'storage_path': source.storagePath,
      'created_by': _userId(),
    });
  }

  /// URL temporaire d'un média (bucket privé). Exige le réseau.
  Future<String> signedUrl(String path) => _client.storage.from(_bucket).createSignedUrl(path, 3600);

  static String _contentType(ResourceKind kind, String ext) => switch ((kind, ext.toLowerCase())) {
        (ResourceKind.video, 'mov') => 'video/quicktime',
        (ResourceKind.video, _) => 'video/mp4',
        (_, 'png') => 'image/png',
        (_, 'webp') => 'image/webp',
        (_, 'heic') => 'image/heic',
        _ => 'image/jpeg',
      };
}

class ResourceTooLarge implements Exception {
  const ResourceTooLarge();
  @override
  String toString() => 'Fichier trop lourd (20 Mo maximum).';
}

final resourceActionsProvider = Provider<ResourceActions>(
  (ref) => ResourceActions(
    ref.watch(supabaseProvider),
    ref.watch(powerSyncProvider),
    () => ref.read(userProvider)?.id,
  ),
);

/// URL signée d'un média, mise en cache le temps de l'écran (une par chemin).
final resourceUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref.watch(resourceActionsProvider).signedUrl(path),
);
