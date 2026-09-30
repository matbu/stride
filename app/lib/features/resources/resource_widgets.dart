import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../data/models.dart';
import '../../data/queries.dart';
import '../../data/resource_actions.dart';
import '../common.dart';
import 'add_resource.dart';

IconData resourceKindIcon(ResourceKind k) => switch (k) {
      ResourceKind.youtube => Icons.smart_display_outlined,
      ResourceKind.instagram => Icons.camera_alt_outlined,
      ResourceKind.link => Icons.link,
      ResourceKind.image => Icons.photo_outlined,
      ResourceKind.video => Icons.videocam_outlined,
    };

/// Ouvre une ressource : un lien YouTube/Instagram part dans l'app correspondante si elle est
/// installée (lien universel), sinon dans le navigateur ; un média s'affiche dans l'app.
Future<void> openResource(BuildContext context, Resource r) async {
  if (r.kind.isFile) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _MediaViewerScreen(resource: r)),
    );
    return;
  }
  final uri = Uri.tryParse(r.url ?? '');
  if (uri == null) return;
  final ok = await guarded(context, () => launchUrl(uri, mode: LaunchMode.externalApplication));
  if (ok == false && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d’ouvrir ce lien.')));
  }
}

/// Vignette carrée : miniature YouTube ou photo si possible, icône de la nature sinon.
class ResourceThumb extends ConsumerWidget {
  const ResourceThumb({super.key, required this.resource, this.size = 56});
  final Resource resource;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      color: scheme.secondaryContainer,
      child: Icon(resourceKindIcon(resource.kind), color: scheme.onSecondaryContainer),
    );
    String? url = resource.youtubeThumbnail;
    if (resource.kind == ResourceKind.image && resource.storagePath != null) {
      url = ref.watch(resourceUrlProvider(resource.storagePath!)).value;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null
          ? fallback
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

/// Ligne de liste d'une ressource. `onTap` par défaut : l'ouvrir.
class ResourceTile extends StatelessWidget {
  const ResourceTile({super.key, required this.resource, this.trailing, this.onTap, this.showVisibility = false});
  final Resource resource;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showVisibility;

  @override
  Widget build(BuildContext context) {
    final r = resource;
    final meta = [
      r.kind.label,
      if (showVisibility) r.isReference ? 'Publique (autre club)' : (r.isPublic ? 'Publique' : 'Club'),
    ].join(' · ');
    return ListTile(
      key: Key('resource-${r.title}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: ResourceThumb(resource: r),
      title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        r.description.isEmpty ? meta : '$meta\n${r.description}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: onTap ?? () => openResource(context, r),
    );
  }
}

/// Liste des ressources du club. Un coach a un menu par ressource (modifier, supprimer).
class ResourceList extends ConsumerWidget {
  const ResourceList({super.key, required this.resources, required this.manage});
  final List<Resource> resources;
  final bool manage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final r in resources)
          ResourceTile(
            resource: r,
            showVisibility: manage,
            trailing: manage
                ? IconButton(
                    key: Key('resource-menu-${r.title}'),
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _actions(context, ref, r),
                  )
                : null,
          ),
      ],
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref, Resource r) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Ouvrir'),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            if (!r.isReference)
              ListTile(
                key: const Key('resource-edit'),
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Modifier'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
            ListTile(
              key: const Key('resource-delete'),
              leading: const Icon(Icons.delete_outline),
              title: Text(r.isReference ? 'Retirer du club' : 'Supprimer'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'open':
        await openResource(context, r);
      case 'edit':
        await editResource(context, r);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(r.isReference ? 'Retirer la ressource ?' : 'Supprimer la ressource ?'),
            content: Text(r.isReference
                ? '« ${r.title} » ne sera plus dans la bibliothèque du club. Elle reste disponible '
                    'dans les ressources publiques.'
                : '« ${r.title} » sera supprimée pour tout le club'
                    '${r.isPublic ? ', et pour les autres clubs qui l’utilisent' : ''}. '
                    'Les séances qui la citent ne l’afficheront plus.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
            ],
          ),
        );
        if (ok == true && context.mounted) {
          await guarded(context, () => ref.read(resourceActionsProvider).delete(r));
        }
    }
  }
}

/// Ressources attachées à une séance, en lecture (détail de séance côté athlète). Les ids dont
/// la ressource a disparu (supprimée, ou originale dépubliée) sont ignorés.
class SessionResources extends ConsumerWidget {
  const SessionResources({super.key, required this.resourceIds});
  final List<String> resourceIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (resourceIds.isEmpty) return const SizedBox.shrink();
    final all = {for (final r in ref.watch(resourcesProvider).value ?? const <Resource>[]) r.id: r};
    final shown = [for (final id in resourceIds) ?all[id]];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [for (final r in shown) ResourceTile(resource: r)]),
    );
  }
}

/// Photo ou vidéo d'une ressource, via une URL signée (bucket privé : exige le réseau).
class _MediaViewerScreen extends ConsumerWidget {
  const _MediaViewerScreen({required this.resource});
  final Resource resource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(resourceUrlProvider(resource.storagePath!));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(resource.title),
      ),
      body: SafeArea(
        child: url.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(
            child: Text('Impossible de charger le média. Vérifie ta connexion.',
                style: TextStyle(color: Colors.white)),
          ),
          data: (u) => resource.kind == ResourceKind.video
              ? _VideoView(url: u)
              : InteractiveViewer(child: Center(child: Image.network(u))),
        ),
      ),
    );
  }
}

class _VideoView extends StatefulWidget {
  const _VideoView({required this.url});
  final String url;

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  Object? _error;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c
        ..setLooping(true)
        ..play();
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const Center(child: Text('Lecture impossible.', style: TextStyle(color: Colors.white)));
    }
    if (!_c.value.isInitialized) return const Center(child: CircularProgressIndicator());
    return GestureDetector(
      onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c))),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _c,
            builder: (_, v, _) => v.isPlaying
                ? const SizedBox.shrink()
                : const Icon(Icons.play_circle_fill, size: 72, color: Colors.white70),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(_c, allowScrubbing: true, padding: const EdgeInsets.all(12)),
          ),
        ],
      ),
    );
  }
}
