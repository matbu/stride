import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Fait le pont entre PowerSync et Supabase :
///  * fournit le jeton d'authentification pour la synchronisation descendante ;
///  * envoie à Postgres (via l'API REST, donc sous RLS) les écritures faites hors ligne.
class SupabaseConnector extends PowerSyncBackendConnector {
  SupabaseConnector(this._client);

  final SupabaseClient _client;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    var session = _client.auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) {
      session = (await _client.auth.refreshSession()).session;
      if (session == null) return null;
    }
    return PowerSyncCredentials(
      endpoint: Config.powersyncUrl,
      token: session.accessToken,
      userId: session.user.id,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final batch = await database.getCrudBatch();
    if (batch == null) return;

    try {
      for (final op in batch.crud) {
        final table = _client.from(op.table);
        switch (op.op) {
          case UpdateType.put:
            await table.upsert(decodeJsonColumns(op.table, {...?op.opData, 'id': op.id}));
          case UpdateType.patch:
            await table.update(decodeJsonColumns(op.table, op.opData!)).eq('id', op.id);
          case UpdateType.delete:
            await table.delete().eq('id', op.id);
        }
      }
      await batch.complete();
    } on PostgrestException catch (e) {
      if (_isFatal(e)) {
        // Une écriture refusée définitivement (droits, contrainte) ne doit pas bloquer la file
        // pour toujours : on l'abandonne. Les données serveur reprennent le dessus à la
        // prochaine sync.
        // TODO: remonter ces rejets à l'utilisateur ("modification non enregistrée").
        debugPrint('Écriture rejetée (${e.code}): ${e.message}');
        await batch.complete();
      } else {
        rethrow;
      }
    }
  }

  /// Erreurs de données (22xxx), d'intégrité (23xxx), de droits (42501) et refus métier des
  /// triggers (P0001) : réessayer donnerait le même résultat.
  static bool _isFatal(PostgrestException e) {
    final code = e.code ?? '';
    return RegExp(r'^(22|23)').hasMatch(code) || code == '42501' || code == 'P0001';
  }
}

/// Colonnes `jsonb` côté Postgres. En local elles sont du texte : envoyées telles quelles,
/// PostgREST les stockerait comme une *chaîne* JSON et non comme un tableau/objet.
const _jsonColumns = {
  'session_blocks': {'items'},
};

/// Remplace, dans une ligne à envoyer, les colonnes JSON textuelles par leur valeur décodée.
Map<String, Object?> decodeJsonColumns(String table, Map<String, Object?> row) {
  final columns = _jsonColumns[table];
  if (columns == null) return row;
  return {
    for (final e in row.entries)
      e.key: (columns.contains(e.key) && e.value is String) ? jsonDecode(e.value as String) : e.value,
  };
}
