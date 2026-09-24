import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'models.dart';

const _uuid = Uuid();

/// Écritures du calendrier de saison (événements + leurs groupes concernés).
class EventActions {
  EventActions(this._db);
  final PowerSyncDatabase _db;

  /// `id` null : création. `groupIds` vide : concerne tout le club (pas de ligne `event_groups`).
  Future<void> save({
    String? id,
    required String clubId,
    required EventKind kind,
    required String title,
    required String startDate,
    required String endDate,
    String location = '',
    EventPriority? priority,
    String notes = '',
    required Set<String> groupIds,
  }) =>
      _db.writeTransaction((tx) async {
        final eventId = id ?? _uuid.v4();
        if (id == null) {
          await tx.execute(
            'INSERT INTO events (id, club_id, kind, title, start_date, end_date, location, priority, notes) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              eventId, clubId, kind.name, title.trim(), startDate, endDate,
              location.trim(), priority?.dbValue, notes.trim(),
            ],
          );
        } else {
          await tx.execute(
            'UPDATE events SET kind = ?, title = ?, start_date = ?, end_date = ?, location = ?, '
            'priority = ?, notes = ? WHERE id = ?',
            [kind.name, title.trim(), startDate, endDate, location.trim(), priority?.dbValue, notes.trim(), eventId],
          );
          await tx.execute('DELETE FROM event_groups WHERE event_id = ?', [eventId]);
        }
        for (final groupId in groupIds) {
          await tx.execute(
            'INSERT INTO event_groups (id, club_id, event_id, group_id) VALUES (?, ?, ?, ?)',
            [_uuid.v4(), clubId, eventId, groupId],
          );
        }
      });

  Future<void> delete(String id) => _db.writeTransaction((tx) async {
        await tx.execute('DELETE FROM event_groups WHERE event_id = ?', [id]);
        await tx.execute('DELETE FROM events WHERE id = ?', [id]);
      });
}

final eventActionsProvider = Provider<EventActions>((ref) => EventActions(ref.watch(powerSyncProvider)));
