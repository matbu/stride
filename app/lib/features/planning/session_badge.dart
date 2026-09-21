import 'package:flutter/material.dart';

import '../../core/session_icons.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

/// Pastille de type : couleur + icône + libellé (jamais la couleur seule).
class TypeBadge extends StatelessWidget {
  const TypeBadge({super.key, required this.type, this.small = false});
  final SessionType? type;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final color = type?.color ?? Theme.of(context).colorScheme.outline;
    final fg = onColor(color);
    final style = small ? Theme.of(context).textTheme.labelSmall : Theme.of(context).textTheme.labelMedium;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 10, vertical: small ? 3 : 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(sessionIcon(type?.icon ?? ''), size: small ? 13 : 16, color: fg),
          SizedBox(width: small ? 4 : 6),
          Flexible(
            child: Text(
              type?.name ?? 'Séance',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
