import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/notation.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import 'block_card.dart';
import 'session_badge.dart';

/// Séance en lecture seule (vue athlète) : infos et contenu de chaque bloc.
class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.session, this.type, this.groupName});

  final PlannedSession session;
  final SessionType? type;
  final String? groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final blocks = ref.watch(blocksForSessionProvider(session.id)).value ?? const <SessionBlock>[];
    final meta = [
      longDayLabel(parseIsoDate(session.date)),
      if (session.startTime != null) shortTime(session.startTime!),
      if (session.durationMin != null) '${session.durationMin} min',
    ].join(' · ');
    final volume = totalVolumeM(blocks.expand((b) => b.items));

    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Align(alignment: Alignment.centerLeft, child: TypeBadge(type: type)),
              const SizedBox(height: 12),
              Text(session.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                [meta, ?groupName].join('\n'),
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (session.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(session.description, style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: 20),
              if (blocks.isEmpty)
                Text(
                  'Le contenu de la séance n’est pas encore détaillé.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              for (final b in blocks) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(blockKindIcon(b.kind), size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(b.heading, style: theme.textTheme.titleSmall),
                        ]),
                        const SizedBox(height: 8),
                        for (final item in b.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              item.format(),
                              // Gros texte : lisible sur la piste, à distance.
                              style: item.hasEffort
                                  ? theme.textTheme.titleMedium
                                  : theme.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic),
                            ),
                          ),
                        if (b.notes.isNotEmpty) Text(b.notes, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (volume > 0)
                Text('Volume d’effort : ${formatDistance(volume)}', style: theme.textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}
