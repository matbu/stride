import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/actions.dart';
import '../common.dart';

class CreateClubScreen extends ConsumerStatefulWidget {
  const CreateClubScreen({super.key});

  @override
  ConsumerState<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends ConsumerState<CreateClubScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  bool _created = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.length < 2) return;
    setState(() => _busy = true);
    final id = await guarded(context, () => ref.read(clubActionsProvider).createClub(name));
    if (!mounted) return;
    // En cas de succès on garde l'écran en attente : le routeur bascule dès que
    // l'adhésion arrive par la synchronisation.
    setState(() {
      _created = id != null;
      _busy = _created;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FormPage(
      title: 'Créer un club',
      children: [
        Text(
          'Le nom doit être unique. Tu deviens le super coach du club : tu pourras y ajouter '
          'des coachs, créer les groupes et inviter les athlètes.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          key: const Key('club-name'),
          controller: _name,
          enabled: !_busy,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Nom du club'),
          onSubmitted: (_) => _create(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('club-create'),
          onPressed: _busy ? null : _create,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Créer le club'),
        ),
        if (_created) ...[
          const SizedBox(height: 16),
          Text('Club créé, synchronisation en cours…', style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => context.go('/onboarding'),
          child: const Text('Retour'),
        ),
      ],
    );
  }
}
