import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../data/actions.dart';

/// Exécute une action réseau ; en cas d'échec affiche un message lisible et renvoie null.
Future<T?> guarded<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(humanError(e))));
    }
    return null;
  }
}

/// Déconnexion avec garde-fou : la base locale est vidée, donc on prévient s'il reste des
/// modifications hors ligne pas encore envoyées.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final actions = ref.read(accountActionsProvider);
  final pending = await actions.hasPendingUploads();
  if (!context.mounted) return;
  if (pending) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifications non envoyées'),
        content: const Text(
          'Certaines modifications faites hors ligne ne sont pas encore synchronisées. '
          'Si tu te déconnectes maintenant, elles seront perdues.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se déconnecter quand même'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  await actions.signOut();
}

/// Contenu centré, largeur limitée (lisible sur tablette).
class FormPage extends StatelessWidget {
  const FormPage({super.key, required this.children, this.title, this.maxWidth = 440});

  final List<Widget> children;
  final String? title;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: title == null ? null : AppBar(title: Text(title!)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              shrinkWrap: true,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleSmall),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
