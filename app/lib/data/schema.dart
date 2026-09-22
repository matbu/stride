import 'package:powersync/powersync.dart';

/// Schéma de la base locale (SQLite). Il reflète les tables Postgres synchronisées, à un détail
/// près : `created_at` / `updated_at` sont absents. Le serveur les gère, et les omettre évite
/// qu'une insertion locale envoie des NULL qui violeraient les NOT NULL à l'upload.
///
/// Types : uuid, date, heure, enum, jsonb → text ; booléens → integer (0/1).
/// La colonne `id` est implicite.
const schema = Schema([
  Table('clubs', [Column.text('name'), Column.text('created_by')]),
  Table('memberships', [
    Column.text('club_id'),
    Column.text('user_id'),
    Column.text('role'),
    Column.text('status'),
    Column.text('display_name'),
  ]),
  Table('training_groups', [
    Column.text('club_id'),
    Column.text('name'),
    Column.integer('sort_order'),
    Column.integer('archived'),
  ]),
  Table('athletes', [
    Column.text('club_id'),
    Column.text('user_id'),
    Column.text('full_name'),
  ]),
  Table('group_athletes', [
    Column.text('club_id'),
    Column.text('group_id'),
    Column.text('athlete_id'),
    Column.text('user_id'),
  ]),
  // `id` EST l'id de l'athlète (voir la migration `athlete_profile`).
  Table('athlete_profiles', [
    Column.text('club_id'),
    Column.text('user_id'),
    Column.text('bio'),
    Column.text('avatar_path'),
    Column.text('ffa_url'),
  ]),
  Table('athlete_records', [
    Column.text('club_id'),
    Column.text('user_id'),
    Column.text('athlete_id'),
    Column.text('discipline'),
    Column.text('performance'),
    Column.text('achieved_on'),
    Column.text('competition'),
  ]),
  Table('invitations', [
    Column.text('club_id'),
    Column.text('code'),
    Column.text('role'),
    Column.text('athlete_id'),
    Column.integer('max_uses'),
    Column.integer('uses'),
    Column.text('expires_at'),
    Column.text('revoked_at'),
    Column.text('created_by'),
  ]),
  Table('session_types', [
    Column.text('club_id'),
    Column.text('name'),
    Column.text('color'),
    Column.text('icon'),
    Column.integer('sort_order'),
    Column.integer('archived'),
  ]),
  Table('sessions', [
    Column.text('club_id'),
    Column.text('type_id'),
    Column.text('title'),
    Column.text('description'),
    Column.integer('is_template'),
    Column.text('group_id'),
    Column.text('scheduled_date'),
    Column.text('start_time'),
    Column.integer('duration_min'),
    Column.text('location'),
    Column.text('template_id'),
    Column.text('created_by'),
  ]),
  Table('session_blocks', [
    Column.text('club_id'),
    Column.text('session_id'),
    Column.text('group_id'),
    Column.text('kind'),
    Column.integer('position'),
    Column.text('title'),
    Column.text('notes'),
    Column.text('items'),
  ]),
  Table('events', [
    Column.text('club_id'),
    Column.text('kind'),
    Column.text('title'),
    Column.text('start_date'),
    Column.text('end_date'),
    Column.text('location'),
    Column.text('priority'),
    Column.text('notes'),
    Column.text('created_by'),
  ]),
  Table('event_groups', [
    Column.text('club_id'),
    Column.text('event_id'),
    Column.text('group_id'),
  ]),
]);
