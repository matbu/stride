import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../data/import_csv.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../../data/session_actions.dart';
import '../common.dart';

/// Import de séances depuis un CSV : fichier ou texte collé, aperçu ligne par ligne, puis
/// enregistrement des lignes valides (les autres sont ignorées, avec la raison).
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _paste = TextEditingController();
  ImportResult? _result;
  bool _busy = false;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  void _analyse(String text) {
    final types = ref.read(sessionTypesProvider).value ?? const <SessionType>[];
    final groups = ref.read(groupsProvider).value ?? const <Group>[];
    setState(() => _result = buildImport(text, types: types, groups: groups));
  }

  Future<void> _pickFile() async {
    final file = await guarded(context, () => FilePicker.pickFile(type: FileType.any));
    if (file == null || !mounted) return;
    final bytes = await guarded(context, file.readAsBytes);
    if (bytes == null || !mounted) return;
    // Les CSV d'Excel français sont souvent en Windows-1252 : on retombe sur latin1 si l'UTF-8 échoue.
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    _paste.text = text;
    _analyse(text);
  }

  Future<void> _shareTemplate() async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'modele-import-stride.csv'));
    await file.writeAsString('﻿$importTemplateCsv');
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Modèle d’import Stride'));
  }

  Future<void> _import() async {
    final clubId = ref.read(clubIdProvider);
    final result = _result;
    if (clubId == null || result == null) return;
    setState(() => _busy = true);
    final actions = ref.read(sessionActionsProvider);
    final count = result.valid.length;
    final ok = await guarded(context, () async {
      for (final row in result.valid) {
        await actions.save(row.draft!, clubId: clubId);
      }
      return true;
    });
    if (!mounted) return;
    if (ok == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(count == 1 ? '1 séance importée' : '$count séances importées')),
      );
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Lus à l'analyse et à l'import (ref.read) : on les suit ici pour que les flux restent actifs.
    ref.watch(sessionTypesProvider);
    ref.watch(groupsProvider);
    ref.watch(clubIdProvider);
    final result = _result;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Importer un CSV')),
      bottomNavigationBar: (result != null && result.valid.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  key: const Key('import-confirm'),
                  onPressed: _busy ? null : _import,
                  child: Text('Importer ${result.valid.length} ${result.valid.length == 1 ? 'séance' : 'séances'}'),
                ),
              ),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(
                'Une ligne par séance. Colonnes : date, heure, duree_min, groupes, type, titre, '
                'echauffement, corps, retour_au_calme, notes. Sans date, la ligne devient un modèle '
                'de la bibliothèque. Dans les colonnes de contenu, sépare les exercices par | : '
                "10x400 r1' | 3x300 r1'.",
                style: muted,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('import-pick'),
                      onPressed: _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Choisir un fichier'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _shareTemplate,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Fichier modèle'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('import-paste'),
                controller: _paste,
                minLines: 4,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'ou colle le contenu du CSV',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('import-analyse'),
                  onPressed: () => _analyse(_paste.text),
                  child: const Text('Analyser'),
                ),
              ),
              if (result != null) ...[
                const SectionHeader('Aperçu'),
                if (result.fileError != null)
                  Text(result.fileError!, style: TextStyle(color: theme.colorScheme.error))
                else ...[
                  Text(
                    '${result.valid.length} prête(s)'
                    '${result.invalid.isEmpty ? '' : ' · ${result.invalid.length} à corriger (ignorée(s))'}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final row in result.rows) _RowTile(row: row),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RowTile extends ConsumerWidget {
  const _RowTile({required this.row});
  final ImportRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groups = {for (final g in ref.watch(groupsProvider).value ?? const <Group>[]) g.id: g.name};
    final d = row.draft;

    final String subtitle;
    if (d == null) {
      subtitle = row.error!;
    } else {
      final items = d.blocks.fold(0, (n, b) => n + b.items.length);
      subtitle = [
        d.isTemplate
            ? 'Modèle de bibliothèque'
            : '${longDayLabel(parseIsoDate(d.date!))}${d.startTime == null ? '' : ' ${d.startTime}'}'
                ' · ${d.groupIds.map((g) => groups[g] ?? '?').join(', ')}',
        '${d.blocks.length} bloc(s), $items exercice(s)',
      ].join('\n');
    }

    return Card(
      child: ListTile(
        key: Key('import-row-${row.line}'),
        leading: Icon(
          row.isValid ? Icons.check_circle_outline : Icons.error_outline,
          color: row.isValid ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
        title: Text(d?.title ?? 'Ligne ${row.line}'),
        subtitle: Text(d == null ? 'Ligne ${row.line} : $subtitle' : subtitle),
        isThreeLine: d != null,
      ),
    );
  }
}
