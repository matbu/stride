import '../../data/models.dart';

/// Regroupe les séances partageant un `linkedId` (créées ou éditées ensemble pour plusieurs
/// groupes) : une seule carte à l'affichage au lieu d'une par groupe. `rows` : toutes les
/// lignes du lot (une séance seule est un lot à elle seule).
class MergedSession {
  MergedSession(this.rows);
  final List<PlannedSession> rows;
  PlannedSession get primary => rows.first;
  List<String> get groupIds => [for (final r in rows) r.groupId];
}

List<MergedSession> mergeByLinkedId(List<PlannedSession> sessions) {
  final byKey = <String, List<PlannedSession>>{};
  for (final s in sessions) {
    (byKey[s.linkedId ?? s.id] ??= []).add(s);
  }
  return [for (final rows in byKey.values) MergedSession(rows)];
}

/// Noms de groupes joints (« Sprint, Demi-fond ») pour une séance affichée sur plusieurs groupes.
String? groupNamesLabel(List<String> groupIds, Map<String, String> groupNames) {
  final names = [for (final id in groupIds) ?groupNames[id]];
  return names.isEmpty ? null : names.join(', ');
}
