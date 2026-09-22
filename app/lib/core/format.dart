import 'package:intl/intl.dart';

final _iso = DateFormat('yyyy-MM-dd');

/// Les dates de séance sont des jours calendaires, stockés en texte `yyyy-MM-dd`.
String isoDate(DateTime d) => _iso.format(d);

DateTime parseIsoDate(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ajoute des jours calendaires (sûr face au changement d'heure, contrairement à Duration).
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

DateTime mondayOf(DateTime d) => addDays(dateOnly(d), -(d.weekday - 1));

const _weekdayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
String weekdayLetter(DateTime d) => _weekdayLetters[d.weekday - 1];

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String longDayLabel(DateTime d) =>
    _capitalize(DateFormat('EEEE d MMMM', 'fr').format(d));

/// « 12 mai 2026 » — date d'un record personnel.
String mediumDate(DateTime d) => DateFormat('d MMM yyyy', 'fr').format(d);

/// « Septembre 2026 ».
String monthLabel(DateTime firstOfMonth) => _capitalize(DateFormat('MMMM yyyy', 'fr').format(firstOfMonth));

/// « 21 – 27 sept. » ou « 28 sept. – 4 oct. » selon que la semaine chevauche deux mois.
String weekRangeLabel(DateTime monday) {
  final sunday = addDays(monday, 6);
  final start = monday.month == sunday.month
      ? DateFormat('d', 'fr').format(monday)
      : DateFormat('d MMM', 'fr').format(monday);
  return '$start – ${DateFormat('d MMM', 'fr').format(sunday)}';
}

/// `HH:mm:ss` (Postgres) ou `HH:mm` → `HH:mm`.
String shortTime(String t) => t.length >= 5 ? t.substring(0, 5) : t;
