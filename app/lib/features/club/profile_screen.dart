import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/profile_actions.dart';
import '../../data/queries.dart';
import '../common.dart';
import '../legal/privacy_policy_screen.dart';

/// Profil d'un athlète : groupes, photo, description, lien FFA, records personnels,
/// et déconnexion. Photo/description/records/lien FFA sont gérés par l'athlète seul ; un coach
/// les consulte en lecture seule depuis la fiche du club (voir `_AthleteSheet`).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _bio = TextEditingController();
  final _ffaUrl = TextEditingController();
  bool _fieldsSeeded = false;
  bool _dirty = false;
  bool _busy = false;
  bool _uploadingAvatar = false;

  @override
  void dispose() {
    _bio.dispose();
    _ffaUrl.dispose();
    super.dispose();
  }

  /// La première valeur reçue du flux local initialise les champs ; ensuite c'est l'utilisateur
  /// qui en a la main (sinon ses frappes seraient écrasées par chaque nouvelle valeur du flux).
  void _seedFields(AthleteProfile? profile) {
    if (_fieldsSeeded) return;
    _bio.text = profile?.bio ?? '';
    _ffaUrl.text = profile?.ffaUrl ?? '';
    _fieldsSeeded = true;
  }

  Future<void> _saveFields(String athleteId, String clubId) async {
    setState(() => _busy = true);
    await guarded(
      context,
      () => ref.read(profileActionsProvider).saveProfile(
            athleteId: athleteId,
            clubId: clubId,
            bio: _bio.text,
            ffaUrl: _ffaUrl.text,
          ),
    );
    if (mounted) setState(() => _busy = _dirty = false);
  }

  Future<void> _pickAvatar(String athleteId, String clubId) async {
    final file = await guarded(context, () => FilePicker.pickFile(type: FileType.image));
    if (file == null || !mounted) return;
    final bytes = await guarded(context, file.readAsBytes);
    if (bytes == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    await guarded(
      context,
      () => ref.read(profileActionsProvider).uploadAvatar(
            athleteId: athleteId,
            clubId: clubId,
            bytes: bytes,
            ext: file.extension ?? 'jpg',
          ),
    );
    if (mounted) setState(() => _uploadingAvatar = false);
  }

  Future<void> _openFfaLink() async {
    final raw = _ffaUrl.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw');
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _addOrEditRecord(String athleteId, String clubId, {AthleteRecord? existing}) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _RecordSheet(athleteId: athleteId, clubId: clubId, existing: existing),
      );

  Future<void> _deleteRecord(AthleteRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce record ?'),
        content: Text('« ${r.discipline} — ${r.performance} » sera supprimé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await guarded(context, () => ref.read(profileActionsProvider).deleteRecord(r.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(activeMembershipProvider);
    final club = ref.watch(clubProvider).value;
    final athlete = ref.watch(myAthleteProvider);
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final mine = athlete == null
        ? const <String>{}
        : (ref.watch(groupLinksProvider).value?[athlete.id] ?? const <String>{});

    if (me == null || club == null) return const Center(child: CircularProgressIndicator());

    final profile = athlete == null ? null : ref.watch(athleteProfileProvider(athlete.id)).value;
    _seedFields(profile);
    final records = athlete == null
        ? const <AthleteRecord>[]
        : (ref.watch(athleteRecordsProvider(athlete.id)).value ?? const <AthleteRecord>[]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            key: const Key('sign-out'),
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => confirmSignOut(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundImage: profile?.avatarPath == null
                      ? null
                      : NetworkImage(ref.read(profileActionsProvider).avatarUrl(profile!.avatarPath!)),
                  child: profile?.avatarPath == null ? const Icon(Icons.person, size: 44) : null,
                ),
                if (athlete != null)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: IconButton.filled(
                      key: const Key('pick-avatar'),
                      onPressed: _uploadingAvatar ? null : () => _pickAvatar(athlete.id, club.id),
                      icon: _uploadingAvatar
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt_outlined, size: 18),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(me.displayName, style: theme.textTheme.headlineSmall)),
          Center(
            child: Text(
              '${me.role.label} · ${club.name}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (athlete != null) ...[
            const SectionHeader('Description'),
            TextField(
              key: const Key('bio-field'),
              controller: _bio,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Quelques mots sur toi…'),
              onChanged: (_) => setState(() => _dirty = true),
            ),
            const SectionHeader('Fiche FFA'),
            Text(
              'Lien vers ta page athle.fr — juste un lien, tes records officiels ne sont pas récupérés automatiquement.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('ffa-field'),
              controller: _ffaUrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://www.athle.fr/athletes/…',
                suffixIcon: _ffaUrl.text.trim().isEmpty
                    ? null
                    : IconButton(
                        key: const Key('open-ffa-link'),
                        icon: const Icon(Icons.open_in_new),
                        onPressed: _openFfaLink,
                      ),
              ),
              onChanged: (_) => setState(() => _dirty = true),
            ),
            if (_dirty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton(
                  key: const Key('save-profile'),
                  onPressed: _busy ? null : () => _saveFields(athlete.id, club.id),
                  child: const Text('Enregistrer'),
                ),
              ),
            SectionHeader(
              'Records personnels',
              trailing: IconButton(
                key: const Key('add-record'),
                icon: const Icon(Icons.add),
                tooltip: 'Ajouter un record',
                onPressed: () => _addOrEditRecord(athlete.id, club.id),
              ),
            ),
            Text(
              'Tes records d’entraînement ou de compétition non officielle — différents des records FFA ci-dessus.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            if (records.isEmpty) const Text('Aucun record pour le moment.'),
            for (final r in records)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${r.discipline} — ${r.performance}'),
                  subtitle: Text(
                    [
                      if (r.achievedOn != null) mediumDate(parseIsoDate(r.achievedOn!)),
                      if (r.competition.isNotEmpty) r.competition,
                    ].join(' · '),
                  ),
                  onTap: () => _addOrEditRecord(athlete.id, club.id, existing: r),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteRecord(r),
                  ),
                ),
              ),
          ],
          const SectionHeader('Mes groupes d’entraînement'),
          if (groups.isEmpty)
            const Text('Ton club n’a pas encore créé de groupe.')
          else ...[
            Text(
              'Choisis les groupes dont tu veux voir les séances.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in groups)
                  FilterChip(
                    key: Key('my-group-${g.name}'),
                    label: Text(g.name),
                    selected: mine.contains(g.id),
                    onSelected: athlete == null
                        ? null
                        : (on) => ref.read(planningActionsProvider).setGroupMembership(
                              clubId: club.id,
                              athlete: athlete,
                              groupId: g.id,
                              member: on,
                            ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 32),
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Quitter ${club.name} ?'),
                  content: const Text('Tu n’auras plus accès aux séances du club.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitter')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await guarded(context, () => ref.read(clubActionsProvider).leaveClub(club.id));
              }
            },
            child: const Text('Quitter le club'),
          ),
          TextButton(
            onPressed: () => confirmSignOut(context, ref),
            child: const Text('Se déconnecter'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
            ),
            child: const Text('Confidentialité'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => confirmDeleteAccount(context, ref),
            child: const Text('Supprimer mon compte'),
          ),
        ],
      ),
    );
  }
}

/// Ajout ou modification d'un record personnel.
class _RecordSheet extends ConsumerStatefulWidget {
  const _RecordSheet({required this.athleteId, required this.clubId, this.existing});
  final String athleteId;
  final String clubId;
  final AthleteRecord? existing;

  @override
  ConsumerState<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends ConsumerState<_RecordSheet> {
  late final _discipline = TextEditingController(text: widget.existing?.discipline ?? '');
  late final _performance = TextEditingController(text: widget.existing?.performance ?? '');
  late final _competition = TextEditingController(text: widget.existing?.competition ?? '');
  late DateTime? _achievedOn =
      widget.existing?.achievedOn == null ? null : parseIsoDate(widget.existing!.achievedOn!);
  bool _busy = false;

  @override
  void dispose() {
    _discipline.dispose();
    _performance.dispose();
    _competition.dispose();
    super.dispose();
  }

  bool get _valid => _discipline.text.trim().isNotEmpty && _performance.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _achievedOn ?? DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _achievedOn = dateOnly(picked));
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      await ref.read(profileActionsProvider).saveRecord(
            id: widget.existing?.id,
            athleteId: widget.athleteId,
            clubId: widget.clubId,
            discipline: _discipline.text,
            performance: _performance.text,
            achievedOn: _achievedOn == null ? null : isoDate(_achievedOn!),
            competition: _competition.text,
          );
      return true;
    });
    if (!mounted) return;
    if (ok == true) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? 'Nouveau record' : 'Modifier le record',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('record-discipline'),
            controller: _discipline,
            decoration: const InputDecoration(labelText: 'Discipline', hintText: '100 m, Longueur, 10 km…'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('record-performance'),
            controller: _performance,
            decoration: const InputDecoration(labelText: 'Performance', hintText: '11.24, 3:58.12, 6,42 m…'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _competition,
            decoration: const InputDecoration(labelText: 'Compétition (facultatif)'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined),
            label: Text(_achievedOn == null ? 'Ajouter une date' : mediumDate(_achievedOn!)),
            onPressed: _pickDate,
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('record-save'),
            onPressed: (_busy || !_valid) ? null : _save,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
