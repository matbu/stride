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
    this.resourceIds = const [],
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
        resourceIds: decodeResourceIds(r['resource_ids']),
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

  /// Ressources attachées (ids de `resources`, dans l'ordre).
  final List<String> resourceIds;
}

/// Modèle de la bibliothèque : une séance sans groupe ni date.
class Template {
  const Template({
    required this.id,
    required this.typeId,
    required this.title,
    this.description = '',
    this.durationMin,
    this.resourceIds = const [],
  });
  factory Template.fromRow(DbRow r) => Template(
        id: r['id'] as String,
        typeId: r['type_id'] as String,
        title: r['title'] as String,
        description: (r['description'] as String?) ?? '',
        durationMin: r['duration_min'] as int?,
        resourceIds: decodeResourceIds(r['resource_ids']),
      );
  final String id;
  final String typeId;
  final String title;
  final String description;
  final int? durationMin;
  final List<String> resourceIds;
}

/// `sessions.resource_ids` : tableau JSON en texte dans la base locale (null avant la première
/// synchronisation d'une ligne créée par une ancienne version de l'app).
List<String> decodeResourceIds(Object? raw) {
  if (raw is! String || raw.isEmpty) return const [];
  final decoded = jsonDecode(raw);
  return decoded is List ? [for (final id in decoded) id as String] : const [];
}

enum ResourceKind {
  youtube('YouTube'),
  instagram('Instagram'),
  link('Lien'),
  image('Photo'),
  video('Vidéo');

  const ResourceKind(this.label);
  final String label;

  bool get isFile => this == image || this == video;

  static ResourceKind parse(String? s) =>
      values.firstWhere((k) => k.name == s, orElse: () => ResourceKind.link);

  /// Nature d'un lien d'après son hôte : YouTube et Instagram s'ouvrent dans leur app si elle
  /// est installée (liens universels), le reste dans le navigateur.
  static ResourceKind ofUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be' || host.endsWith('youtube.com')) return youtube;
    if (host.endsWith('instagram.com')) return instagram;
    return link;
  }
}

/// Ressource du club : lien (YouTube, Instagram, web) ou média (photo, vidéo) stocké dans le
/// bucket privé 'resources'. `sourceId` non null = référence à une ressource publique d'un
/// autre club, dont le contenu est recopié par le serveur (non modifiable ici).
class Resource {
  const Resource({
    required this.id,
    required this.clubId,
    required this.kind,
    required this.title,
    this.description = '',
    this.url,
    this.storagePath,
    this.isPublic = false,
    this.sourceId,
  });
  factory Resource.fromRow(DbRow r) => Resource(
        id: r['id'] as String,
        clubId: r['club_id'] as String,
        kind: ResourceKind.parse(r['kind'] as String?),
        title: (r['title'] as String?) ?? '',
        description: (r['description'] as String?) ?? '',
        url: r['url'] as String?,
        storagePath: r['storage_path'] as String?,
        isPublic: r['visibility'] == 'public',
        sourceId: r['source_id'] as String?,
      );
  final String id;
  final String clubId;
  final ResourceKind kind;
  final String title;
  final String description;
  final String? url;
  final String? storagePath;
  final bool isPublic;
  final String? sourceId;

  bool get isReference => sourceId != null;

  /// Miniature YouTube, sans clé d'API (image publique de la vidéo) ; null sinon.
  String? get youtubeThumbnail {
    if (kind != ResourceKind.youtube || url == null) return null;
    final id = youtubeVideoId(Uri.tryParse(url!));
    return id == null ? null : 'https://img.youtube.com/vi/$id/mqdefault.jpg';
  }
}

/// Id de vidéo d'une URL YouTube : youtu.be/ID, youtube.com/watch?v=ID, /shorts/ID, /embed/ID.
String? youtubeVideoId(Uri? uri) {
  if (uri == null) return null;
  if (uri.host.toLowerCase() == 'youtu.be') return uri.pathSegments.firstOrNull;
  final v = uri.queryParameters['v'];
  if (v != null && v.isNotEmpty) return v;
  final segs = uri.pathSegments;
  if (segs.length >= 2 && (segs[0] == 'shorts' || segs[0] == 'embed' || segs[0] == 'live')) return segs[1];
  return null;
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

// --- Calendrier de saison ------------------------------------------------------------------

enum EventKind {
  competition('Compétition'),
  deadline('Échéance'),
  camp('Stage'),
  other('Autre');

  const EventKind(this.label);
  final String label;

  static EventKind parse(String? s) =>
      values.firstWhere((k) => k.name == s, orElse: () => EventKind.other);
}

/// Correspond à l'enum Postgres `event_priority` ('A', 'B', 'C') — les valeurs stockées sont en
/// majuscule, d'où le mapping explicite plutôt qu'un simple `values.byName`.
enum EventPriority {
  a('A'),
  b('B'),
  c('C');

  const EventPriority(this.dbValue);
  final String dbValue;

  static EventPriority? parse(String? s) => switch (s) {
        'A' => EventPriority.a,
        'B' => EventPriority.b,
        'C' => EventPriority.c,
        _ => null,
      };
}

/// Un événement du calendrier de saison (compétition, échéance, stage...). `startDate`/
/// `endDate` au format `yyyy-MM-dd`. Sans ligne dans `event_groups`, concerne tout le club.
class Event {
  const Event({
    required this.id,
    required this.kind,
    required this.title,
    required this.startDate,
    required this.endDate,
    this.location = '',
    this.priority,
    this.notes = '',
  });

  factory Event.fromRow(DbRow r) => Event(
        id: r['id'] as String,
        kind: EventKind.parse(r['kind'] as String?),
        title: r['title'] as String,
        startDate: r['start_date'] as String,
        endDate: r['end_date'] as String,
        location: (r['location'] as String?) ?? '',
        priority: EventPriority.parse(r['priority'] as String?),
        notes: (r['notes'] as String?) ?? '',
      );

  final String id;
  final EventKind kind;
  final String title;
  final String startDate;
  final String endDate;
  final String location;
  final EventPriority? priority;
  final String notes;
}
