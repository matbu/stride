import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'drafts.dart';
import 'models.dart';

const _uuid = Uuid();

/// Écritures des séances et de leurs blocs. Tout passe par la base locale : ça marche hors
/// ligne, et PowerSync envoie les changements au serveur ensuite.
///
/// Un enregistrement est une seule transaction locale : séance et blocs sont écrits ensemble
/// ou pas du tout.
class SessionActions {
  SessionActions(this._db, this._userId);
  final PowerSyncDatabase _db;
  final String? Function() _userId;

  /// Enregistre un brouillon.
  ///  * modèle : une ligne sans groupe ni date ;
  ///  * séance existante : mise à jour, et blocs synchronisés (ajoutés, modifiés, supprimés) ;
  ///  * nouvelle séance : une séance par groupe coché, chacune avec sa copie des blocs. Si elle
  ///    n'a pas été placée depuis un modèle existant (`templateId` null), elle rejoint aussi la
  ///    bibliothèque automatiquement (une seule fois, même si plusieurs groupes sont cochés).
  Future<void> save(SessionDraft d, {required String clubId}) {
    if (d.typeId == null) throw ArgumentError('type manquant');
    return _db.writeTransaction((tx) async {
      if (d.isTemplate) {
        final id = d.id ?? _uuid.v4();
        await _writeSession(tx, id, d, clubId, isNew: d.id == null);
        await _writeBlocks(tx, id, clubId, null, d.blocks);
      } else if (d.id != null) {
        final group = d.groupIds.single;
        await _writeSession(tx, d.id!, d, clubId, groupId: group, isNew: false);
        await _writeBlocks(tx, d.id!, clubId, group, d.blocks);
      } else {
        if (d.groupIds.isEmpty) throw ArgumentError('groupe manquant');
        for (final group in d.groupIds) {
          final id = _uuid.v4();
          await _writeSession(tx, id, d, clubId, groupId: group, isNew: true);
          await _writeBlocks(tx, id, clubId, group, [for (final b in d.blocks) b.copy(freshId: true)]);
        }
        // Séance créée à la main (pas depuis un modèle existant) : elle rejoint aussi la
        // bibliothèque, une seule fois même si placée pour plusieurs groupes à la fois.
        if (d.templateId == null) {
          final templateId = _uuid.v4();
          final template = SessionDraft(
            isTemplate: true,
            typeId: d.typeId,
            title: d.title,
            description: d.description,
            durationMin: d.durationMin,
          );
          await _writeSession(tx, templateId, template, clubId, isNew: true);
          await _writeBlocks(tx, templateId, clubId, null, [for (final b in d.blocks) b.copy(freshId: true)]);
        }
      }
    });
  }

  Future<void> _writeSession(
    SqliteWriteContext tx,
    String id,
    SessionDraft d,
    String clubId, {
    String? groupId,
    required bool isNew,
  }) async {
    final date = d.isTemplate ? null : d.date;
    final time = d.isTemplate || d.startTime == null ? null : '${d.startTime}:00';
    if (isNew) {
      await tx.execute(
        'INSERT INTO sessions (id, club_id, type_id, title, description, is_template, group_id, '
        'scheduled_date, start_time, duration_min, location, template_id, created_by) '
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, ?)",
        [
          id, clubId, d.typeId, d.title.trim(), d.description, d.isTemplate ? 1 : 0,
          groupId, date, time, d.durationMin, d.templateId, _userId(),
        ],
      );
    } else {
      await tx.execute(
        'UPDATE sessions SET type_id = ?, title = ?, description = ?, group_id = ?, '
        'scheduled_date = ?, start_time = ?, duration_min = ? WHERE id = ?',
        [d.typeId, d.title.trim(), d.description, groupId, date, time, d.durationMin, id],
      );
    }
  }

  Future<void> _writeBlocks(
    SqliteWriteContext tx,
    String sessionId,
    String clubId,
    String? groupId,
    List<BlockDraft> blocks,
  ) async {
    final existing = {
      for (final r in await tx.getAll('SELECT id FROM session_blocks WHERE session_id = ?', [sessionId]))
        r['id'] as String,
    };
    final keep = {for (final b in blocks) b.id};
    for (final gone in existing.difference(keep)) {
      await tx.execute('DELETE FROM session_blocks WHERE id = ?', [gone]);
    }
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final items = encodeItems(b.items);
      if (existing.contains(b.id)) {
        await tx.execute(
          'UPDATE session_blocks SET group_id = ?, kind = ?, position = ?, title = ?, notes = ?, '
          'items = ? WHERE id = ?',
          [groupId, b.kind.name, i, b.title, b.notes, items, b.id],
        );
      } else {
        await tx.execute(
          'INSERT INTO session_blocks (id, club_id, session_id, group_id, kind, position, title, '
          'notes, items) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [b.id, clubId, sessionId, groupId, b.kind.name, i, b.title, b.notes, items],
        );
      }
    }
  }

  /// Relit une séance (ou un modèle) et ses blocs depuis la base locale.
  Future<SessionDraft> loadDraft(String sessionId) async {
    final s = await _db.get('SELECT * FROM sessions WHERE id = ?', [sessionId]);
    final blocks = await _db.getAll(
      'SELECT * FROM session_blocks WHERE session_id = ? ORDER BY position',
      [sessionId],
    );
    final isTemplate = s['is_template'] == 1;
    return SessionDraft(
      id: sessionId,
      isTemplate: isTemplate,
      typeId: s['type_id'] as String,
      title: s['title'] as String,
      description: (s['description'] as String?) ?? '',
      groupIds: {if (s['group_id'] != null) s['group_id'] as String},
      date: s['scheduled_date'] as String?,
      startTime: (s['start_time'] as String?)?.substring(0, 5),
      durationMin: s['duration_min'] as int?,
      templateId: s['template_id'] as String?,
      blocks: [for (final r in blocks) BlockDraft.from(SessionBlock.fromRow(r))],
    );
  }

  /// Place un modèle : une copie indépendante (séance + blocs) par groupe. Le modèle peut
  /// ensuite évoluer sans réécrire les séances déjà placées.
  Future<void> place({
    required String templateId,
    required String clubId,
    required Set<String> groupIds,
    required String date,
    String? startTime,
  }) async {
    final t = await loadDraft(templateId);
    await save(
      SessionDraft(
        typeId: t.typeId,
        title: t.title,
        description: t.description,
        groupIds: groupIds,
        date: date,
        startTime: startTime,
        durationMin: t.durationMin,
        templateId: templateId,
        blocks: [for (final b in t.blocks) b.copy(freshId: true)],
      ),
      clubId: clubId,
    );
  }

  /// Copie une séance placée dans la bibliothèque.
  Future<void> saveAsTemplate(String sessionId, {required String clubId}) async {
    final s = await loadDraft(sessionId);
    await save(
      SessionDraft(
        isTemplate: true,
        typeId: s.typeId,
        title: s.title,
        description: s.description,
        durationMin: s.durationMin,
        blocks: [for (final b in s.blocks) b.copy(freshId: true)],
      ),
      clubId: clubId,
    );
  }

  Future<void> move(String sessionId, String isoDate) =>
      _db.execute('UPDATE sessions SET scheduled_date = ? WHERE id = ?', [isoDate, sessionId]);

  /// Supprime la séance et ses blocs (il n'y a pas de cascade dans la base locale).
  Future<void> delete(String sessionId) => _db.writeTransaction((tx) async {
        await tx.execute('DELETE FROM session_blocks WHERE session_id = ?', [sessionId]);
        await tx.execute('DELETE FROM sessions WHERE id = ?', [sessionId]);
      });

  /// Un athlète marque sa propre séance comme faite (façon Pronote). L'existence de la ligne
  /// vaut « fait » ; un coach ne peut pas marquer à la place d'un athlète (RLS).
  Future<void> markDone(String sessionId, String athleteId, {required String clubId}) => _db.execute(
        'INSERT INTO session_completions (id, session_id, athlete_id, club_id) VALUES (?, ?, ?, ?)',
        [_uuid.v4(), sessionId, athleteId, clubId],
      );

  Future<void> markNotDone(String sessionId, String athleteId) => _db.execute(
        'DELETE FROM session_completions WHERE session_id = ? AND athlete_id = ?',
        [sessionId, athleteId],
      );
}

final sessionActionsProvider = Provider<SessionActions>(
  (ref) => SessionActions(ref.watch(powerSyncProvider), () => ref.read(userProvider)?.id),
);
