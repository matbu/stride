import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/database.dart';
import '../common.dart';

/// Premier écran d'un compte sans club : créer le sien ou rejoindre un club existant.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = (ref.watch(userProvider)?.userMetadata?['display_name'] as String?) ?? '';
    final first = name.trim().split(' ').first;

    return FormPage(
      children: [
        const SizedBox(height: 32),
        Text(
          first.isEmpty ? 'Bienvenue' : 'Bienvenue $first',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Pour commencer, crée ton club ou rejoins-en un.',
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        _ChoiceCard(
          key: const Key('choice-create'),
          icon: Icons.add_business_outlined,
          title: 'Créer un club',
          subtitle: 'Tu en seras le super coach : groupes, coachs, athlètes, séances.',
          onTap: () => context.go('/onboarding/create'),
        ),
        const SizedBox(height: 12),
        _ChoiceCard(
          key: const Key('choice-join'),
          icon: Icons.group_add_outlined,
          title: 'Rejoindre un club',
          subtitle: 'Avec un code d’invitation, ou en demandant l’accès.',
          onTap: () => context.go('/onboarding/join'),
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: () => confirmSignOut(context, ref),
          child: const Text('Se déconnecter'),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
