import 'package:flutter/material.dart';

import '../../data/drafts.dart';
import '../../data/models.dart';
import 'place_sheet.dart';
import 'session_detail.dart';
import 'session_editor.dart';

/// Un coach ouvre l'éditeur ; un athlète la fiche en lecture seule.
void openSession(
  BuildContext context,
  PlannedSession session, {
  required bool isCoach,
  SessionType? type,
  String? groupName,
}) {
  if (isCoach) {
    openSessionEditor(context, SessionDraft.fromPlanned(session));
  } else {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SessionDetailScreen(session: session, type: type, groupName: groupName),
    ));
  }
}

/// Bouton « + » : nouvelle séance, ou séance issue d'un modèle de la bibliothèque.
Future<void> startNewSession(BuildContext context, {DateTime? date, String? groupId}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('new-blank'),
            leading: const Icon(Icons.edit_note),
            title: const Text('Nouvelle séance'),
            subtitle: const Text('Partir de zéro'),
            onTap: () => Navigator.pop(ctx, 'blank'),
          ),
          ListTile(
            key: const Key('new-from-template'),
            leading: const Icon(Icons.library_books_outlined),
            title: const Text('Depuis un modèle'),
            subtitle: const Text('Placer une séance de la bibliothèque'),
            onTap: () => Navigator.pop(ctx, 'template'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'blank') {
    await openSessionEditor(context, newSessionDraft(date: date, groupId: groupId));
  } else {
    final t = await showTemplatePicker(context);
    if (t != null && context.mounted) {
      await showPlaceSheet(context, template: t, date: date, groupId: groupId);
    }
  }
}
