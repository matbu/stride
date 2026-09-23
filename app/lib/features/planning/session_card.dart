import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import 'session_badge.dart';

/// Carte de séance. `compact` : version étroite pour les colonnes de la vue tablette.
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.session,
    this.type,
    this.groupName,
    this.onTap,
    this.compact = false,
    this.done,
    this.onToggleDone,
  });

  final PlannedSession session;
  final SessionType? type;
  final String? groupName;
  final VoidCallback? onTap;
  final bool compact;

  /// Null : pas d'indicateur « fait » (pas de contexte athlète). Sinon, l'état de complétion.
  final bool? done;

  /// Non null seulement pour l'athlète sur sa propre séance : un coach consulte, sans marquer.
  final VoidCallback? onToggleDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = type?.color ?? theme.colorScheme.outline;
    final meta = [
      if (session.startTime != null) shortTime(session.startTime!),
      if (session.durationMin != null) '${session.durationMin} min',
    ].join(' · ');
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: compact ? 5 : 8, color: color),
              Expanded(
                child: Padding(
                  padding: compact ? const EdgeInsets.fromLTRB(8, 8, 6, 8) : const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TypeBadge(type: type, small: true),
                            const SizedBox(height: 6),
                            Text(
                              session.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (meta.isNotEmpty) Text(meta, style: secondary),
                            if (groupName != null)
                              Text(groupName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Passe à la ligne plutôt que de déborder (petit écran, grande police).
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              runSpacing: 4,
                              children: [
                                TypeBadge(type: type),
                                if (meta.isNotEmpty) Text(meta, style: theme.textTheme.labelLarge),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(session.title, style: theme.textTheme.titleMedium),
                            if (groupName != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                groupName!,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              if (done != null) _doneIndicator(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _doneIndicator(ThemeData theme) {
    final icon = Icon(
      done! ? Icons.check_circle : Icons.radio_button_unchecked,
      color: done! ? Colors.green : theme.colorScheme.outline,
      size: compact ? 18 : 22,
    );
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: onToggleDone == null
          ? Padding(padding: const EdgeInsets.all(8), child: icon)
          : IconButton(
              key: Key('done-toggle-${session.id}'),
              tooltip: done! ? 'Marquer non faite' : 'Marquer faite',
              icon: icon,
              onPressed: onToggleDone,
            ),
    );
  }
}
