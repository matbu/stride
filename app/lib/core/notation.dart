/// Saisie rapide d'un exercice d'athlétisme, et son affichage.
///
/// Notation acceptée (majuscules/minuscules indifférentes) :
///
///     10x400 r1'            10 × 400 m, récupération 1 minute
///     3x300 r1'30           3 × 300 m, récupération 1'30
///     6 x 1'30 r 45"        6 × 1'30 d'effort, récupération 45 secondes
///     4x2km @10k            4 × 2 km à l'allure 10k
///     5x200 r200m           récupération en distance (trot)
///     10x400 r1' 3x300 r1'  plusieurs exercices sur une même ligne
///     1h @endurance         effort de durée, sans répétition
///     Footing en côte       texte libre : gardé comme note
///
/// Règles :
///  * un nombre seul est une distance en mètres (≥ 30) ; `km`/`m` explicites sinon ;
///  * durées : `1h`, `1h30`, `10min`, `2'`, `1'30`, `30"`, `45s` (secondes et minutes après
///    `'` ou `h` sur deux chiffres : `1'05`) ;
///  * dans `r…`, un nombre seul est en secondes ;
///  * une nouvelle répétition `N x …` au milieu d'une ligne démarre un nouvel exercice ;
///    saut de ligne et `;` séparent aussi. Ce qui n'est pas reconnu devient la note de
///    l'exercice précédent.
library;

class BlockItem {
  const BlockItem({
    this.reps = 1,
    this.distanceM,
    this.durationS,
    this.recoveryS,
    this.recoveryM,
    this.intensity = '',
    this.note = '',
  });

  factory BlockItem.fromJson(Map<String, Object?> j) => BlockItem(
        reps: (j['reps'] as num?)?.toInt() ?? 1,
        distanceM: (j['distance_m'] as num?)?.toInt(),
        durationS: (j['duration_s'] as num?)?.toInt(),
        recoveryS: (j['recovery_s'] as num?)?.toInt(),
        recoveryM: (j['recovery_m'] as num?)?.toInt(),
        intensity: (j['intensity'] as String?) ?? '',
        note: (j['note'] as String?) ?? '',
      );

  final int reps;

  /// Distance d'un effort, en mètres.
  final int? distanceM;

  /// Durée d'un effort, en secondes.
  final int? durationS;
  final int? recoveryS;

  /// Récupération en distance (trot), en mètres.
  final int? recoveryM;
  final String intensity;
  final String note;

  bool get hasEffort => distanceM != null || durationS != null;

  /// Distance d'effort cumulée, en mètres (les efforts en durée ne comptent pas).
  int get volumeM => reps * (distanceM ?? 0);

  Map<String, Object?> toJson() => {
        'reps': reps,
        'distance_m': ?distanceM,
        'duration_s': ?durationS,
        'recovery_s': ?recoveryS,
        'recovery_m': ?recoveryM,
        if (intensity.isNotEmpty) 'intensity': intensity,
        if (note.isNotEmpty) 'note': note,
      };

  BlockItem withNote(String note) => BlockItem(
        reps: reps,
        distanceM: distanceM,
        durationS: durationS,
        recoveryS: recoveryS,
        recoveryM: recoveryM,
        intensity: intensity,
        note: note,
      );

  /// Forme saisissable : `parseNotation(item.toNotation())` redonne le même exercice.
  String toNotation() {
    final b = StringBuffer();
    if (hasEffort) {
      if (reps > 1) b.write('${reps}x');
      b.write(distanceM != null ? _distanceNotation(distanceM!) : formatDuration(durationS!));
      if (recoveryS != null) b.write(' r${formatDuration(recoveryS!)}');
      if (recoveryM != null) b.write(' r${_distanceNotation(recoveryM!, forceUnit: true)}');
      if (intensity.isNotEmpty) b.write(' @$intensity');
      if (note.isNotEmpty) b.write(' $note');
    } else {
      b.write(note);
    }
    return b.toString();
  }

  /// Forme lisible, pour l'affichage.
  String format() {
    if (!hasEffort) return note;
    final parts = <String>[];
    final effort = distanceM != null ? formatDistance(distanceM!) : formatDuration(durationS!);
    parts.add(reps > 1 ? '$reps × $effort' : effort);
    if (recoveryS != null) parts.add('récup ${formatDuration(recoveryS!)}');
    if (recoveryM != null) parts.add('récup ${formatDistance(recoveryM!)}');
    if (intensity.isNotEmpty) parts.add('@$intensity');
    if (note.isNotEmpty) parts.add(note);
    return parts.join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is BlockItem &&
      other.reps == reps &&
      other.distanceM == distanceM &&
      other.durationS == durationS &&
      other.recoveryS == recoveryS &&
      other.recoveryM == recoveryM &&
      other.intensity == intensity &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(reps, distanceM, durationS, recoveryS, recoveryM, intensity, note);

  @override
  String toString() => 'BlockItem(${toNotation()})';
}

int totalVolumeM(Iterable<BlockItem> items) => items.fold(0, (s, i) => s + i.volumeM);

/// `1'30`, `2'`, `30"`, `1h`, `1h30`
String formatDuration(int seconds) {
  if (seconds >= 3600 && seconds % 60 == 0) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }
  if (seconds >= 60) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? "$m'" : "$m'${s.toString().padLeft(2, '0')}";
  }
  return '$seconds"';
}

/// `400 m`, `1,5 km`
String formatDistance(int metres) {
  if (metres < 1000) return '$metres m';
  final km = metres / 1000;
  final text = km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toString();
  return '${text.replaceAll('.', ',')} km';
}

String _distanceNotation(int m, {bool forceUnit = false}) {
  if (m >= 1000 && m % 100 == 0) {
    final km = m / 1000;
    return '${km == km.roundToDouble() ? km.toStringAsFixed(0) : km}km';
  }
  if (m >= _minBareMetres && m < 1000 && !forceUnit) return '$m';
  return '${m}m';
}

const _minBareMetres = 30;

// --- Analyse -----------------------------------------------------------------------------

/// Transforme un texte en exercices. Ne lève jamais d'exception : ce qui n'est pas reconnu
/// est conservé comme note.
List<BlockItem> parseNotation(String input) {
  final items = <BlockItem>[];
  for (final segment in input.split(RegExp(r'[\n;]'))) {
    final text = segment.trim();
    if (text.isNotEmpty) items.addAll(_parseSegment(text));
  }
  return items;
}

RegExp _re(String p) => RegExp(p, caseSensitive: false, unicode: true);

final _repsRe = _re(r'(\d{1,3})\s*[x×*]\s*(?=\d)');
final _nextRepsRe = _re(r'\d{1,3}\s*[x×*]\s*\d');
final _hourRe = _re(r'(\d+)\s*h(?!\p{L})(?:(\d{2})(?!\d))?');
final _minRe = _re(r'(\d+)\s*(?:min|mn)(?!\p{L})');
final _secRe = _re(r'''(\d+)\s*(?:''|["”″]|sec(?!\p{L})|s(?!\p{L}))''');
final _primeRe = _re(r'''(\d+)\s*['’′](?:(\d{2})(?!\d))?(?:''|["”″])?''');
final _distRe = _re(r'(\d+(?:[.,]\d+)?)(?:\s*(km|m)(?!\p{L}))?');
final _recPrefixRe = _re(r'(?:r[eé]cup(?:[eé]ration)?|rec|r)\.?\s*:?\s*');
final _bareSecondsRe = _re(r'(\d+)(?![\p{L}\d])');
final _intensityRe = _re(r'(?:@|allure\s+)\s*([^\s;]+)(?:\s+(vma|vo2max|vo2|fcm|fc|max)(?!\p{L}))?');

class _Cursor {
  _Cursor(this.s);
  final String s;
  int i = 0;

  bool get done => i >= s.length;

  void skipSpaces() {
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) {
      i++;
    }
  }

  Match? match(RegExp re) => re.matchAsPrefix(s, i);
}

bool _isLetter(String ch) => RegExp(r'\p{L}', unicode: true).hasMatch(ch);

List<BlockItem> _parseSegment(String text) {
  final c = _Cursor(text);
  final items = <BlockItem>[];

  void addNote(String note) {
    final n = note.replaceFirst(RegExp(r'^[\s,+\-–]+'), '').trim();
    if (n.isEmpty) return;
    if (items.isEmpty) {
      items.add(BlockItem(note: n));
    } else {
      final last = items.removeLast();
      items.add(last.withNote(last.note.isEmpty ? n : '${last.note} $n'));
    }
  }

  while (true) {
    c.skipSpaces();
    if (c.done) break;
    final item = _tryItem(c, allowBare: items.isEmpty);
    if (item != null) {
      items.add(item);
      continue;
    }
    // Texte libre jusqu'au prochain "N x …".
    var end = text.length;
    for (final m in _nextRepsRe.allMatches(text, c.i + 1)) {
      final prev = text[m.start - 1];
      if (!_isLetter(prev) && !RegExp(r'\d').hasMatch(prev)) {
        end = m.start;
        break;
      }
    }
    addNote(text.substring(c.i, end));
    c.i = end;
  }
  return items;
}

BlockItem? _tryItem(_Cursor c, {required bool allowBare}) {
  final start = c.i;
  var reps = 1;
  final rm = c.match(_repsRe);
  if (rm != null) {
    reps = int.parse(rm[1]!);
    if (reps < 1) return null;
    c.i = rm.end;
  } else if (!allowBare) {
    return null;
  }

  final durationS = _readDuration(c);
  final distanceM = durationS == null ? _readDistance(c, bareOk: true) : null;
  if (durationS == null && distanceM == null) {
    c.i = start;
    return null;
  }

  int? recoveryS;
  int? recoveryM;
  var intensity = '';
  // Récupération et intensité peuvent venir dans n'importe quel ordre.
  var progressed = true;
  while (progressed) {
    progressed = false;
    c.skipSpaces();
    if (recoveryS == null && recoveryM == null) {
      final r = _tryRecovery(c);
      if (r != null) {
        recoveryS = r.$1;
        recoveryM = r.$2;
        progressed = true;
        continue;
      }
    }
    if (intensity.isEmpty) {
      final m = c.match(_intensityRe);
      if (m != null) {
        intensity = m[2] == null ? m[1]! : '${m[1]} ${m[2]}';
        c.i = m.end;
        progressed = true;
      }
    }
  }

  return BlockItem(
    reps: reps,
    distanceM: distanceM,
    durationS: durationS,
    recoveryS: recoveryS,
    recoveryM: recoveryM,
    intensity: intensity,
  );
}

int? _readDuration(_Cursor c) {
  var m = c.match(_hourRe);
  if (m != null) {
    c.i = m.end;
    return int.parse(m[1]!) * 3600 + (m[2] == null ? 0 : int.parse(m[2]!) * 60);
  }
  m = c.match(_minRe);
  if (m != null) {
    c.i = m.end;
    return int.parse(m[1]!) * 60;
  }
  // Les secondes d'abord : `30''` ne doit pas être lu comme 30 minutes.
  m = c.match(_secRe);
  if (m != null) {
    c.i = m.end;
    return int.parse(m[1]!);
  }
  m = c.match(_primeRe);
  if (m != null) {
    c.i = m.end;
    return int.parse(m[1]!) * 60 + (m[2] == null ? 0 : int.parse(m[2]!));
  }
  return null;
}

/// Distance en mètres. Sans unité, seul un nombre entier ≥ 30 est accepté (évite de prendre
/// « 2 séries » pour 2 mètres).
int? _readDistance(_Cursor c, {required bool bareOk}) {
  final m = c.match(_distRe);
  if (m == null) return null;
  final unit = m[2]?.toLowerCase();
  final value = double.parse(m[1]!.replaceAll(',', '.'));
  if (unit == null) {
    final isInt = !m[1]!.contains(RegExp(r'[.,]'));
    if (!bareOk || !isInt || value < _minBareMetres) return null;
    if (m.end < c.s.length && _isLetter(c.s[m.end]) && c.s[m.end].toLowerCase() != 'r') {
      return null;
    }
  }
  c.i = m.end;
  return (unit == 'km' ? value * 1000 : value).round();
}

/// Renvoie (secondes, mètres) ou null si ce n'est pas une récupération.
(int?, int?)? _tryRecovery(_Cursor c) {
  final save = c.i;
  if (c.match(_recPrefixRe) == null) return null;
  c.i = _recPrefixRe.matchAsPrefix(c.s, c.i)!.end;

  final d = _readDuration(c);
  if (d != null) return (d, null);

  final m = c.match(_distRe);
  if (m != null && m[2] != null) {
    c.i = m.end;
    final v = double.parse(m[1]!.replaceAll(',', '.'));
    return (null, (m[2]!.toLowerCase() == 'km' ? v * 1000 : v).round());
  }

  final b = c.match(_bareSecondsRe);
  if (b != null) {
    c.i = b.end;
    return (int.parse(b[1]!), null);
  }

  c.i = save;
  return null;
}
