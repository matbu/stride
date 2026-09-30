import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models.dart';
import '../../data/queries.dart';
import '../../data/resource_actions.dart';
import '../common.dart';
import 'resource_widgets.dart';

/// Point d'entrée « Nouvelle ressource » : un lien, un média du téléphone, ou une ressource
/// publique d'un autre club.
Future<void> startAddResource(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('add-resource-link'),
            leading: const Icon(Icons.link),
            title: const Text('Lien YouTube, Instagram ou web'),
            subtitle: const Text('S’ouvre dans l’app concernée si elle est installée'),
            onTap: () => Navigator.pop(ctx, 'link'),
          ),
          ListTile(
            key: const Key('add-resource-media'),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Photo ou vidéo du téléphone'),
            subtitle: const Text('Vidéo courte : 20 Mo maximum'),
            onTap: () => Navigator.pop(ctx, 'media'),
          ),
          ListTile(
            key: const Key('add-resource-public'),
            leading: const Icon(Icons.public),
            title: const Text('Parcourir les ressources publiques'),
            subtitle: const Text('Partagées par d’autres clubs'),
            onTap: () => Navigator.pop(ctx, 'public'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'link':
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _ResourceFormScreen()));
    case 'media':
      final media = await _pickMedia(context);
      if (media == null || !context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ResourceFormScreen(media: media)));
    case 'public':
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PublicResourcesScreen()));
  }
}

Future<void> editResource(BuildContext context, Resource r) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _ResourceFormScreen(existing: r)),
    );

class _PickedMedia {
  const _PickedMedia(this.kind, this.bytes, this.ext);
  final ResourceKind kind;
  final Uint8List bytes;
  final String ext;
}

const _videoExts = {'mp4', 'mov', 'm4v'};

/// Photo ou vidéo de la galerie. Les photos sont réduites à la source (1600 px, JPEG) ; une
/// vidéo trop lourde est refusée ici plutôt qu'après un envoi voué à l'échec.
Future<_PickedMedia?> _pickMedia(BuildContext context) async {
  final file = await guarded(
    context,
    () => ImagePicker().pickMedia(maxWidth: 1600, maxHeight: 1600, imageQuality: 80),
  );
  if (file == null || !context.mounted) return null;
  final name = file.name.toLowerCase();
  final ext = name.contains('.') ? name.split('.').last : 'jpg';
  final isVideo = (file.mimeType?.startsWith('video/') ?? false) || _videoExts.contains(ext);
  if (await file.length() > maxResourceFileBytes) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Fichier trop lourd (20 Mo maximum). Raccourcis la vidéo et réessaie.'),
      ));
    }
    return null;
  }
  final bytes = await file.readAsBytes();
  return _PickedMedia(isVideo ? ResourceKind.video : ResourceKind.image, bytes, ext == 'jpeg' ? 'jpg' : ext);
}

/// Formulaire d'une ressource : lien (création), média choisi (création) ou ressource existante
/// (modification). Une nouvelle ressource exige un choix explicite de confidentialité.
class _ResourceFormScreen extends ConsumerStatefulWidget {
  const _ResourceFormScreen({this.media, this.existing});
  final _PickedMedia? media;
  final Resource? existing;

  @override
  ConsumerState<_ResourceFormScreen> createState() => _ResourceFormScreenState();
}

class _ResourceFormScreenState extends ConsumerState<_ResourceFormScreen> {
  late final _url = TextEditingController(text: widget.existing?.url ?? '');
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _description = TextEditingController(text: widget.existing?.description ?? '');
  late bool? _isPublic = widget.existing?.isPublic;
  bool _busy = false;
  String? _fetchedFor;

  bool get _isLink => widget.media == null && widget.existing == null;
  bool get _editing => widget.existing != null;

  Uri? get _parsedUrl {
    final raw = _url.text.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw.startsWith(RegExp('https?://', caseSensitive: false)) ? raw : 'https://$raw');
    return (uri == null || uri.host.isEmpty || !uri.host.contains('.')) ? null : uri;
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty && _isPublic != null && (!_isLink || _parsedUrl != null);

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Titre d'une vidéo YouTube via oEmbed (public, sans clé), pour préremplir le titre.
  Future<void> _prefillTitle() async {
    final uri = _parsedUrl;
    if (uri == null || _title.text.trim().isNotEmpty || ResourceKind.ofUrl(uri) != ResourceKind.youtube) return;
    if (_fetchedFor == uri.toString()) return;
    _fetchedFor = uri.toString();
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(Uri.https('www.youtube.com', '/oembed', {'url': uri.toString(), 'format': 'json'}));
      final res = await req.close();
      if (res.statusCode != 200) return;
      final json = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final title = json['title'];
      if (mounted && title is String && _title.text.trim().isEmpty) setState(() => _title.text = title);
      client.close();
    } catch (_) {
      // Best effort : le coach saisit le titre lui-même.
    }
  }

  Future<void> _save() async {
    final clubId = ref.read(clubIdProvider);
    if (clubId == null || !_valid) return;
    final actions = ref.read(resourceActionsProvider);
    setState(() => _busy = true);

    if (_isLink) {
      final url = _parsedUrl!.toString();
      final existing = await actions.findPublicByUrl(clubId: clubId, url: url);
      if (!mounted) return;
      if (existing != null) {
        setState(() => _busy = false);
        final useIt = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Déjà partagée publiquement'),
            content: Text('Un autre club a déjà publié ce lien : « ${existing.title} ». '
                'L’ajouter tel quel à ton club ?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Créer la mienne')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ajouter celle-ci')),
            ],
          ),
        );
        if (!mounted || useIt == null) return;
        setState(() => _busy = true);
        if (useIt) {
          final ok = await guarded(context, () async {
            await actions.addPublic(clubId: clubId, source: existing);
            return true;
          });
          return _done(ok == true);
        }
      }
    }

    final ok = await guarded(context, () async {
      final r = widget.existing;
      final m = widget.media;
      if (r != null) {
        await actions.update(r, title: _title.text, description: _description.text, isPublic: _isPublic!);
      } else if (m != null) {
        await actions.addFile(
          clubId: clubId,
          kind: m.kind,
          bytes: m.bytes,
          ext: m.ext,
          title: _title.text,
          description: _description.text,
          isPublic: _isPublic!,
        );
      } else {
        await actions.addLink(
          clubId: clubId,
          url: _parsedUrl!.toString(),
          title: _title.text,
          description: _description.text,
          isPublic: _isPublic!,
        );
      }
      return true;
    });
    _done(ok == true);
  }

  void _done(bool ok) {
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = widget.media;
    final existing = widget.existing;
    final wasPublic = existing?.isPublic ?? false;
    // Le club est lu à l'enregistrement (ref.read) : on le suit ici pour que le flux reste actif.
    ref.watch(clubIdProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Modifier la ressource' : 'Nouvelle ressource')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            key: const Key('resource-save'),
            onPressed: (_busy || !_valid) ? null : _save,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_editing ? 'Enregistrer' : (m != null ? 'Envoyer' : 'Ajouter')),
          ),
        ),
      ),
      body: FormPage(
        maxWidth: 560,
        children: [
          if (m != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: m.kind == ResourceKind.image
                  ? Image.memory(m.bytes, height: 200, fit: BoxFit.cover)
                  : Container(
                      height: 120,
                      color: theme.colorScheme.secondaryContainer,
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.videocam_outlined, size: 40, color: theme.colorScheme.onSecondaryContainer),
                          const SizedBox(height: 4),
                          Text('Vidéo · ${(m.bytes.length / (1024 * 1024)).toStringAsFixed(1)} Mo'),
                        ]),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
          ],
          if (_isLink) ...[
            TextField(
              key: const Key('resource-url'),
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Lien',
                hintText: 'https://youtu.be/… ou https://www.instagram.com/reel/…',
              ),
              onChanged: (_) {
                setState(() {});
                _prefillTitle();
              },
            ),
            const SizedBox(height: 16),
          ],
          if (existing?.url != null) ...[
            Text(existing!.url!, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
          ],
          TextField(
            key: const Key('resource-title'),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Titre', hintText: 'ex. Posture en starting-blocks'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('resource-description'),
            controller: _description,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description (facultatif)'),
          ),
          const SizedBox(height: 20),
          Text('Visible par', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            key: const Key('resource-visibility'),
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.groups_outlined), label: Text('Mon club')),
              ButtonSegment(value: true, icon: Icon(Icons.public), label: Text('Public')),
            ],
            selected: {?_isPublic},
            onSelectionChanged: (s) => setState(() => _isPublic = s.firstOrNull ?? _isPublic),
          ),
          const SizedBox(height: 8),
          Text(
            switch (_isPublic) {
              null => 'Choisis qui peut voir cette ressource.',
              false => wasPublic
                  ? 'Seuls les membres du club la verront. Les autres clubs qui l’avaient ajoutée la perdront.'
                  : 'Seuls les membres du club la verront.',
              true => 'Tous les clubs de TrackClub pourront la voir et l’ajouter à leur bibliothèque.',
            },
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Ressources publiques des autres clubs : recherche par titre, ajout au club par référence.
class PublicResourcesScreen extends ConsumerStatefulWidget {
  const PublicResourcesScreen({super.key});

  @override
  ConsumerState<PublicResourcesScreen> createState() => _PublicResourcesScreenState();
}

class _PublicResourcesScreenState extends ConsumerState<PublicResourcesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Resource>? _results;
  Object? _error;
  final _adding = <String>{};

  @override
  void initState() {
    super.initState();
    // Le club peut ne pas être encore connu au premier affichage : on charge dès qu'il l'est.
    ref.listenManual<String?>(clubIdProvider, (_, id) {
      if (id != null) _load();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final clubId = ref.read(clubIdProvider);
    if (clubId == null) return;
    try {
      final list = await ref.read(resourceActionsProvider).browsePublic(clubId: clubId, search: _search.text);
      if (mounted) {
        setState(() {
          _results = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _add(Resource r) async {
    final clubId = ref.read(clubIdProvider);
    if (clubId == null) return;
    setState(() => _adding.add(r.id));
    await guarded(context, () => ref.read(resourceActionsProvider).addPublic(clubId: clubId, source: r));
    if (mounted) setState(() => _adding.remove(r.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = {
      for (final r in ref.watch(resourcesProvider).value ?? const <Resource>[])
        if (r.sourceId != null) r.sourceId!,
    };
    final results = _results;
    ref.watch(clubIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ressources publiques')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const Key('public-resources-search'),
              controller: _search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher par titre'),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _load);
              },
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('Impossible de charger les ressources publiques. Vérifie ta connexion.',
                          textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                    ),
                  )
                : results == null
                    ? const Center(child: CircularProgressIndicator())
                    : results.isEmpty
                        ? Center(
                            child: Text(
                              _search.text.trim().isEmpty
                                  ? 'Aucune ressource publique pour le moment.'
                                  : 'Aucun résultat.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 32),
                              itemCount: results.length,
                              itemBuilder: (context, i) {
                                final r = results[i];
                                return ResourceTile(
                                  resource: r,
                                  trailing: mine.contains(r.id)
                                      ? const Chip(label: Text('Ajoutée'), avatar: Icon(Icons.check, size: 16))
                                      : _adding.contains(r.id)
                                          ? const SizedBox(
                                              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                          : FilledButton.tonal(
                                              key: Key('public-add-${r.title}'),
                                              onPressed: () => _add(r),
                                              child: const Text('Ajouter'),
                                            ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// Choix des ressources à attacher à une séance (éditeur de séance). Renvoie la nouvelle liste
/// d'ids, ou null si annulé. Les ids déjà attachés gardent leur ordre, les nouveaux s'ajoutent.
Future<List<String>?> pickSessionResources(BuildContext context, List<String> current) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ResourcePickerSheet(initial: current),
  );
}

class _ResourcePickerSheet extends ConsumerStatefulWidget {
  const _ResourcePickerSheet({required this.initial});
  final List<String> initial;

  @override
  ConsumerState<_ResourcePickerSheet> createState() => _ResourcePickerSheetState();
}

class _ResourcePickerSheetState extends ConsumerState<_ResourcePickerSheet> {
  late final List<String> _selected = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resources = ref.watch(resourcesProvider).value ?? const <Resource>[];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(children: [
                Expanded(child: Text('Ressources de la séance', style: theme.textTheme.titleMedium)),
                TextButton.icon(
                  key: const Key('picker-new-resource'),
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle'),
                  onPressed: () => startAddResource(context),
                ),
              ]),
            ),
            Flexible(
              child: resources.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Aucune ressource dans la bibliothèque. Ajoute-en une avec « Nouvelle ».'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in resources)
                          CheckboxListTile(
                            key: Key('pick-resource-${r.title}'),
                            secondary: ResourceThumb(resource: r, size: 40),
                            title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(r.kind.label),
                            value: _selected.contains(r.id),
                            onChanged: (on) => setState(() => on == true ? _selected.add(r.id) : _selected.remove(r.id)),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('picker-confirm'),
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('Valider'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
