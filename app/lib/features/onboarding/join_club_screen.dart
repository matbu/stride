import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/actions.dart';
import '../../data/models.dart';
import '../common.dart';

/// Deux voies : un code d'invitation (adhésion immédiate, avec le rôle de l'invitation) ou
/// une recherche de club suivie d'une demande que les coachs valident.
class JoinClubScreen extends StatelessWidget {
  const JoinClubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rejoindre un club'),
          leading: BackButton(onPressed: () => context.go('/onboarding')),
          bottom: const TabBar(tabs: [
            Tab(text: 'J’ai un code'),
            Tab(text: 'Chercher un club'),
          ]),
        ),
        body: const SafeArea(
          child: TabBarView(children: [_CodeTab(), _SearchTab()]),
        ),
      ),
    );
  }
}

class _CodeTab extends ConsumerStatefulWidget {
  const _CodeTab();

  @override
  ConsumerState<_CodeTab> createState() => _CodeTabState();
}

class _CodeTabState extends ConsumerState<_CodeTab> {
  final _code = TextEditingController();
  InvitationPreview? _preview;
  bool _busy = false;
  bool _joined = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final preview = await guarded(context, () => ref.read(clubActionsProvider).previewInvitation(_code.text));
    if (!mounted) return;
    setState(() => _busy = false);
    if (preview == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code introuvable. Vérifie-le et réessaie.')),
      );
    }
    setState(() => _preview = preview);
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      await ref.read(clubActionsProvider).acceptInvitation(_code.text);
      return true;
    });
    if (!mounted) return;
    setState(() {
      _joined = ok == true;
      _busy = _joined;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Ton coach t’a envoyé un code d’invitation : saisis-le pour entrer directement dans le club.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('invite-code'),
          controller: _code,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z -]'))],
          decoration: const InputDecoration(labelText: 'Code', hintText: 'XXXX-XXXX-XXXX'),
          onChanged: (_) => setState(() => _preview = null),
          onSubmitted: (_) => _check(),
        ),
        const SizedBox(height: 16),
        if (preview == null)
          FilledButton(
            onPressed: _busy ? null : _check,
            child: const Text('Continuer'),
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preview.clubName, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    preview.valid
                        ? 'Tu rejoindras le club en tant que ${preview.role.label.toLowerCase()}.'
                        : 'Ce code a expiré ou a déjà été utilisé.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('invite-accept'),
            onPressed: (_busy || !preview.valid) ? null : _accept,
            child: Text('Rejoindre ${preview.clubName}'),
          ),
        ],
        if (_joined) ...[
          const SizedBox(height: 16),
          Text('Bienvenue ! Synchronisation en cours…', style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class _SearchTab extends ConsumerStatefulWidget {
  const _SearchTab();

  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<Club>? _results; // null : pas encore cherché (ou moins de 2 caractères)
  bool _searching = false;
  Club? _selected;
  bool _busy = false;
  ClubRole _role = ClubRole.athlete;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    setState(() => _selected = null);
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    final results = await guarded(context, () => ref.read(clubActionsProvider).searchClubs(q));
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = results ?? [];
    });
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    await guarded(context, () => ref.read(clubActionsProvider).requestJoin(_selected!.id, _role));
    // Succès : la demande arrive par la synchronisation et le routeur ouvre l'écran d'attente.
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Cherche ton club par son nom. Les coachs recevront ta demande et devront la valider.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('club-search'),
          controller: _query,
          enabled: !_busy,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Nom du club',
            helperText: 'Au moins 2 lettres.',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
          onChanged: _onChanged,
          onSubmitted: (t) {
            _debounce?.cancel();
            final q = t.trim();
            if (q.length >= 2) _search(q);
          },
        ),
        const SizedBox(height: 8),
        if (selected == null) ...[
          if (_results != null && _results!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Aucun club trouvé.'),
            ),
          for (final c in _results ?? const <Club>[])
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(c.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => _selected = c),
              ),
            ),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(selected.name, style: theme.textTheme.titleLarge)),
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _selected = null),
                        child: const Text('Changer'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Je rejoins en tant que…'),
                  const SizedBox(height: 8),
                  SegmentedButton<ClubRole>(
                    segments: const [
                      ButtonSegment(value: ClubRole.athlete, label: Text('Athlète')),
                      ButtonSegment(value: ClubRole.coach, label: Text('Coach')),
                    ],
                    selected: {_role},
                    onSelectionChanged: (s) => setState(() => _role = s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('join-request'),
            onPressed: _busy ? null : _request,
            child: const Text('Envoyer la demande'),
          ),
        ],
      ],
    );
  }
}
