import 'dart:convert';

import 'package:flutter/painting.dart' show Color;

import '../core/notation.dart';
import '../core/theme.dart';

typedef DbRow = Map<String, Object?>;

enum ClubRole {
  owner('Super coach'),
  coach('Coach'),
  athlete('Athlète');

  const ClubRole(this.label);
  final String label;

  bool get isCoach => this != athlete;

  static ClubRole parse(String s) => values.byName(s);
}

class Membership {
  const Membership({
    required this.id,
    required this.clubId,
    required this.userId,
    required this.role,
    required this.isActive,
    required this.displayName,
  });

  factory Membership.fromRow(DbRow r) => Membership(
        id: r['id'] as String,
        clubId: r['club_id'] as String,
        userId: r['user_id'] as String,
        role: ClubRole.parse(r['role'] as String),
        isActive: r['status'] == 'active',
        displayName: (r['display_name'] as String?) ?? '',
      );

  final String id;
  final String clubId;
  final String userId;
  final ClubRole role;
  final bool isActive;
  final String displayName;
}

class Club {
  const Club({required this.id, required this.name});
  factory Club.fromRow(DbRow r) =>
      Club(id: r['id'] as String, name: r['name'] as String);
  final String id;
  final String name;
}

/// Profil libre-service du club (description, logo) — voir `club_profiles`. `clubId` EST l'id
/// du club (relation 1:1, table d'extension, comme `AthleteProfile` avec l'athlète).
class ClubProfile {
  const ClubProfile({required this.clubId, this.description = '', this.logoPath});
  factory ClubProfile.fromRow(DbRow r) => ClubProfile(
        clubId: r['id'] as String,
        description: (r['description'] as String?) ?? '',
        logoPath: r['logo_path'] as String?,
      );
  final String clubId;
  final String description;
  final String? logoPath;
}

class Group {
  const Group({required this.id, required this.name});
  factory Group.fromRow(DbRow r) =>
      Group(id: r['id'] as String, name: r['name'] as String);
  final String id;
  final String name;
}

class Athlete {
  const Athlete({required this.id, required this.fullName, this.userId});
  factory Athlete.fromRow(DbRow r) => Athlete(
        id: r['id'] as String,
        fullName: r['full_name'] as String,
        userId: r['user_id'] as String?,
      );
  final String id;
  final String fullName;

  /// Null tant que l'athlète n'a pas rejoint avec un compte.
  final String? userId;
  bool get hasAccount => userId != null;
}

/// Profil en libre-service d'un athlète : `id` est celui de l'`Athlete` (table d'extension 1:1).
class AthleteProfile {
  const AthleteProfile({required this.athleteId, this.bio = '', this.avatarPath, this.ffaUrl});
  factory AthleteProfile.fromRow(DbRow r) => AthleteProfile(
        athleteId: r['id'] as String,
        bio: (r['bio'] as String?) ?? '',
        avatarPath: r['avatar_path'] as String?,
        ffaUrl: r['ffa_url'] as String?,
      );
  final String athleteId;
  final String bio;
  final String? avatarPath;
  final String? ffaUrl;
}

/// Record personnel (entraînement ou compétition non officielle) — différent des records FFA.
/// `performance` est du texte libre : les unités varient trop selon la discipline pour trier.
class AthleteRecord {
  const AthleteRecord({
    required this.id,
    required this.athleteId,
    required this.discipline,
    required this.performance,
    this.achievedOn,
    this.competition = '',
  });
  factory AthleteRecord.fromRow(DbRow r) => AthleteRecord(
        id: r['id'] as String,
        athleteId: r['athlete_id'] as String,
        discipline: r['discipline'] as String,
        performance: r['performance'] as String,
        achievedOn: r['achieved_on'] as String?,
        competition: (r['competition'] as String?) ?? '',
      );
  final String id;
  final String athleteId;
  final String discipline;
  final String performance;
  /// `yyyy-MM-dd`, ou null si non précisée.
  final String? achievedOn;
  final String competition;
}

class SessionType {
  const SessionType({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
  });
  factory SessionType.fromRow(DbRow r) => SessionType(
        id: r['id'] as String,
        name: r['name'] as String,
        color: parseHexColor(r['color'] as String),
        icon: (r['icon'] as String?) ?? 'run',
      );
  final String id;
  final String name;
  final Color color;
  final String icon;
}

class PlannedSession {
  const PlannedSession({
    required this.id,
    required this.typeId,
    required this.title,
    required this.groupId,
    required this.date,
    this.startTime,
    this.durationMin,
    this.description = '',
    this.linkedId,
  });
  factory PlannedSession.fromRow(DbRow r) => PlannedSession(
        id: r['id'] as String,
        typeId: r['type_id'] as String,
        title: r['title'] as String,
        groupId: r['group_id'] as String,
        date: r['scheduled_date'] as String,
        startTime: r['start_time'] as String?,
        durationMin: r['duration_min'] as int?,
        description: (r['description'] as String?) ?? '',
        linkedId: r['linked_id'] as String?,
      );
  final String id;
  final String typeId;
  final String title;
  final String groupId;

  /// `yyyy-MM-dd`
  final String date;
  final String? startTime;
  final int? durationMin;
  final String description;

  /// Partagé par les séances créées (ou éditées) ensemble pour plusieurs groupes : permet de les
  /// afficher comme une seule séance multi-groupes. Null pour une séance à un seul groupe.
  final String? linkedId;
}

/// Modèle de la bibliothèque : une séance sans groupe ni date.
class Template {
  const Template({
    required this.id,
    required this.typeId,
    required this.title,
    this.description = '',
    this.durationMin,
  });
  factory Template.fromRow(DbRow r) => Template(
        id: r['id'] as String,
        typeId: r['type_id'] as String,
        title: r['title'] as String,
        description: (r['description'] as String?) ?? '',
        durationMin: r['duration_min'] as int?,
      );
  final String id;
  final String typeId;
  final String title;
  final String description;
  final int? durationMin;
}

enum BlockKind {
  warmup('Échauffement'),
  main('Corps de séance'),
  cooldown('Retour au calme'),
  other('Autre');

  const BlockKind(this.label);
  final String label;

  static BlockKind parse(String? s) =>
      values.firstWhere((k) => k.name == s, orElse: () => BlockKind.other);
}

class SessionBlock {
  const SessionBlock({
    required this.id,
    required this.sessionId,
    required this.kind,
    required this.position,
    required this.title,
    required this.notes,
    required this.items,
  });

  factory SessionBlock.fromRow(DbRow r) => SessionBlock(
        id: r['id'] as String,
        sessionId: r['session_id'] as String,
        kind: BlockKind.parse(r['kind'] as String?),
        position: (r['position'] as int?) ?? 0,
        title: (r['title'] as String?) ?? '',
        notes: (r['notes'] as String?) ?? '',
        items: decodeItems(r['items']),
      );

  final String id;
  final String sessionId;
  final BlockKind kind;
  final int position;
  final String title;
  final String notes;
  final List<BlockItem> items;

  String get heading => title.isNotEmpty ? title : kind.label;
}

/// Lit la colonne `items` (texte JSON en local). Tolère une valeur absente ou corrompue.
List<BlockItem> decodeItems(Object? raw) {
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map) BlockItem.fromJson(e.cast<String, Object?>()),
    ];
  } catch (_) {
    return const [];
  }
}

String encodeItems(List<BlockItem> items) => jsonEncode([for (final i in items) i.toJson()]);
