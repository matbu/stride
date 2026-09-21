/// Lecture de CSV tolérante : séparateur `;` (Excel français), `,` ou tabulation détecté sur
/// l'en-tête ; champs entre guillemets, guillemets doublés, retours à la ligne dans un champ.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  var src = text;
  if (src.startsWith('﻿')) src = src.substring(1);
  final sep = delimiter ?? detectDelimiter(src);

  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var fieldWasQuoted = false;

  void endField() {
    row.add(fieldWasQuoted ? field.toString() : field.toString().trim());
    field.clear();
    fieldWasQuoted = false;
  }

  void endRow() {
    endField();
    // Les lignes entièrement vides sont ignorées.
    if (row.any((f) => f.isNotEmpty) || row.length > 1) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < src.length; i++) {
    final ch = src[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < src.length && src[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"' && field.isEmpty) {
      inQuotes = true;
      fieldWasQuoted = true;
    } else if (ch == sep) {
      endField();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < src.length && src[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty || fieldWasQuoted) endRow();

  // Retire les lignes qui ne contiennent que des champs vides.
  return rows.where((r) => r.any((f) => f.isNotEmpty)).toList();
}

/// Choisit le séparateur le plus fréquent (hors guillemets) sur la première ligne.
String detectDelimiter(String text) {
  final counts = {';': 0, ',': 0, '\t': 0};
  var inQuotes = false;
  for (final ch in text.split('')) {
    if (ch == '"') inQuotes = !inQuotes;
    if (!inQuotes) {
      if (ch == '\n' || ch == '\r') break;
      if (counts.containsKey(ch)) counts[ch] = counts[ch]! + 1;
    }
  }
  final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
  return best.value == 0 ? ';' : best.key;
}

/// Échappe un champ pour l'écriture d'un CSV.
String csvField(String value, {String delimiter = ';'}) {
  final needsQuotes =
      value.contains(delimiter) || value.contains('"') || value.contains('\n') || value.contains('\r');
  return needsQuotes ? '"${value.replaceAll('"', '""')}"' : value;
}
