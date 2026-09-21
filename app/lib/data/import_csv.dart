import '../core/csv.dart';
import '../core/notation.dart';
import 'drafts.dart';
import 'models.dart';

/// Import de séances depuis un CSV : une ligne = une séance (ou un modèle si la date est vide).
///
/// Colonnes (l'ordre est libre, les noms tolèrent accents et majuscules) :
///
///     date ; heure ; duree_min ; groupes ; type ; titre ; echauffement ; corps ; retour_au_calme ; notes
///
///  * `date` : `2026-09-28`, `28/09/2026` ou `28/09/26`. Vide = modèle de bibliothèque.
///  * `groupes` : un ou plusieurs noms séparés par `|`. Obligatoire quand il y a une date.
///  * `type` : nom d'un type de séance du club (obligatoire). `titre` aussi.
///  * `echauffement`, `corps`, `retour_au_calme` : exercices en saisie rapide, séparés par `|`
///    ou par un retour à la ligne : `10x400 r1' | 3x300 r1'`.
const importTemplateCsv = '''date;heure;duree_min;groupes;type;titre;echauffement;corps;retour_au_calme;notes
2026-09-28;18:30;90;Sprint|Demi-fond;Fractionné;10 × 400 + 3 × 300;Footing 15' | 4x60 r30";10x400 r1' | 3x300 r1';Footing 10';Piste couverte
2026-09-29;18:30;60;Demi-fond;Endurance;Footing 1h;;1h @endurance;;
;;75;;Seuil / Tempo;Modèle : 3 × 10' seuil;Footing 15';3x10' @seuil r2';Footing 10';Modèle pour la bibliothèque
''';

class ImportRow {
  const ImportRow({required this.line, this.draft, this.error});

  /// Numéro de ligne dans le fichier (l'en-tête est la ligne 1).
  final int line;
  final SessionDraft? draft;
  final String? error;

  bool get isValid => draft != null;
}

class ImportResult {
  const ImportResult(this.rows, {this.fileError});
  final List<ImportRow> rows;

  /// Problème global (fichier vide, colonnes obligatoires absentes).
  final String? fileError;

  Iterable<ImportRow> get valid => rows.where((r) => r.isValid);
  Iterable<ImportRow> get invalid => rows.where((r) => !r.isValid);
}

const _aliases = <String, List<String>>{
  'date': ['date', 'jour'],
  'time': ['heure', 'time', 'horaire'],
  'duration': ['duree', 'dureemin', 'duration', 'duree_min'],
  'groups': ['groupe', 'groupes', 'group', 'groups'],
  'type': ['type', 'typedeseance'],
  'title': ['titre', 'title', 'nom', 'intitule'],
  'warmup': ['echauffement', 'warmup'],
  'main': ['corps', 'corpsdeseance', 'main', 'contenu', 'content'],
  'cooldown': ['retour', 'retouraucalme', 'retourcalme', 'cooldown'],
  'notes': ['notes', 'note', 'description', 'commentaire', 'commentaires'],
};

/// Minuscules, sans accents, sans ponctuation : « Retour au calme » → `retouraucalme`.
String normalizeKey(String s) {
  const from = 'àâäáãçéèêëíìîïñóòôöõúùûüýÿœ';
  const to = 'aaaaaceeeeiiiinooooouuuuyyo';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    final c = i >= 0 ? to[i] : ch;
    if (RegExp(r'[a-z0-9]').hasMatch(c)) b.write(c);
  }
  return b.toString();
}

ImportResult buildImport(
  String csv, {
  required List<SessionType> types,
  required List<Group> groups,
}) {
  final table = parseCsv(csv);
  if (table.length < 2) {
    return const ImportResult([], fileError: 'Le fichier est vide ou ne contient que l’en-tête.');
  }

  // Colonne → index, par alias.
  final columns = <String, int>{};
  final header = table.first.map(normalizeKey).toList();
  for (final entry in _aliases.entries) {
    final idx = header.indexWhere((h) => entry.value.map(normalizeKey).contains(h));
    if (idx >= 0) columns[entry.key] = idx;
  }
  final missing = [
    if (!columns.containsKey('type')) 'type',
    if (!columns.containsKey('title')) 'titre',
  ];
  if (missing.isNotEmpty) {
    return ImportResult(
      const [],
      fileError: 'Colonne(s) obligatoire(s) absente(s) : ${missing.join(', ')}. '
          'Vérifie la première ligne du fichier.',
    );
  }

  String cell(List<String> row, String key) {
    final i = columns[key];
    return (i == null || i >= row.length) ? '' : row[i].trim();
  }

  final rows = <ImportRow>[];
  for (var r = 1; r < table.length; r++) {
    rows.add(_buildRow(r + 1, table[r], cell, types, groups));
  }
  return ImportResult(rows);
}

ImportRow _buildRow(
  int line,
  List<String> row,
  String Function(List<String>, String) cell,
  List<SessionType> types,
  List<Group> groups,
) {
  ImportRow fail(String msg) => ImportRow(line: line, error: msg);

  final title = cell(row, 'title');
  if (title.isEmpty) return fail('titre manquant');

  final typeName = cell(row, 'type');
  final type = _matchType(typeName, types);
  if (typeName.isEmpty) return fail('type manquant');
  if (type == null) {
    return fail('type inconnu « $typeName » (types du club : ${types.map((t) => t.name).join(', ')})');
  }

  final dateText = cell(row, 'date');
  String? date;
  if (dateText.isNotEmpty) {
    date = parseImportDate(dateText);
    if (date == null) return fail('date illisible « $dateText » (attendu : 2026-09-28 ou 28/09/2026)');
  }

  final groupIds = <String>{};
  final groupText = cell(row, 'groups');
  if (date != null) {
    if (groupText.isEmpty) return fail('groupe manquant (obligatoire quand il y a une date)');
    for (final name in groupText.split(RegExp(r'[|,]')).map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      final g = groups.where((g) => normalizeKey(g.name) == normalizeKey(name)).firstOrNull;
      if (g == null) {
        return fail('groupe inconnu « $name » (groupes du club : ${groups.map((g) => g.name).join(', ')})');
      }
      groupIds.add(g.id);
    }
  }

  String? startTime;
  final timeText = cell(row, 'time');
  if (timeText.isNotEmpty) {
    startTime = parseImportTime(timeText);
    if (startTime == null) return fail('heure illisible « $timeText » (attendu : 18:30)');
  }

  int? duration;
  final durText = cell(row, 'duration');
  if (durText.isNotEmpty) {
    duration = int.tryParse(durText);
    if (duration == null || duration <= 0) return fail('durée illisible « $durText » (minutes, ex. 90)');
  }

  final blocks = <BlockDraft>[
    for (final (key, kind) in [
      ('warmup', BlockKind.warmup),
      ('main', BlockKind.main),
      ('cooldown', BlockKind.cooldown),
    ])
      if (parseNotation(cell(row, key).replaceAll('|', '\n')) case final items when items.isNotEmpty)
        BlockDraft(kind: kind, items: items),
  ];

  return ImportRow(
    line: line,
    draft: SessionDraft(
      isTemplate: date == null,
      typeId: type.id,
      title: title,
      description: cell(row, 'notes'),
      groupIds: groupIds,
      date: date,
      startTime: startTime,
      durationMin: duration,
      blocks: blocks,
    ),
  );
}

SessionType? _matchType(String name, List<SessionType> types) {
  final key = normalizeKey(name);
  if (key.isEmpty) return null;
  final exact = types.where((t) => normalizeKey(t.name) == key);
  if (exact.isNotEmpty) return exact.first;
  // Préfixe non ambigu : « Seuil » → « Seuil / Tempo ».
  final prefix = types.where((t) => normalizeKey(t.name).startsWith(key)).toList();
  return prefix.length == 1 ? prefix.first : null;
}

/// `2026-09-28`, `28/09/2026`, `28-09-2026`, `28/09/26` → `yyyy-MM-dd` (ou null).
String? parseImportDate(String s) {
  final t = s.trim();
  int? y, m, d;
  var match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
  if (match != null) {
    y = int.parse(match[1]!);
    m = int.parse(match[2]!);
    d = int.parse(match[3]!);
  } else {
    match = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2}|\d{4})$').firstMatch(t);
    if (match == null) return null;
    d = int.parse(match[1]!);
    m = int.parse(match[2]!);
    y = int.parse(match[3]!);
    if (y < 100) y += 2000;
  }
  final date = DateTime(y, m, d);
  // DateTime normalise 31/02 en mars : on refuse plutôt que de décaler silencieusement.
  if (date.year != y || date.month != m || date.day != d) return null;
  return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

/// `18:30`, `18h30`, `18h`, `8:05` → `HH:mm` (ou null).
String? parseImportTime(String s) {
  final match = RegExp(r'^(\d{1,2})\s*[:hH]\s*(\d{2})?$').firstMatch(s.trim());
  if (match == null) return null;
  final h = int.parse(match[1]!);
  final m = match[2] == null ? 0 : int.parse(match[2]!);
  if (h > 23 || m > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
