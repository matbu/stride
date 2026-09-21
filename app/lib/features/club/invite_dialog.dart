import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/actions.dart';
import '../../data/models.dart';

/// Affiche un code d'invitation avec copie et partage (WhatsApp, SMS, etc.).
Future<void> showInviteDialog(
  BuildContext context, {
  required String code,
  required String clubName,
  required ClubRole role,
  String? forName,
}) {
  final formatted = formatInviteCode(code);
  final message = 'Rejoins $clubName sur Coach : ouvre l’app, choisis « Rejoindre un club » '
      'puis saisis le code $formatted.';

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(forName == null ? 'Code d’invitation' : 'Invitation pour $forName'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SelectableText(
              formatted,
              key: const Key('invite-code-value'),
              style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Rôle : ${role.label}. Valable 14 jours.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: formatted));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Code copié')));
            }
          },
          child: const Text('Copier'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => SharePlus.instance.share(ShareParams(text: message)),
          child: const Text('Partager'),
        ),
      ],
    ),
  );
}
