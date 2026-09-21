import 'package:flutter/material.dart';

import '../../core/notation.dart';
import '../../data/drafts.dart';
import '../../data/models.dart';

const _kindIcons = {
  BlockKind.warmup: Icons.wb_sunny_outlined,
  BlockKind.main: Icons.local_fire_department_outlined,
  BlockKind.cooldown: Icons.ac_unit,
  BlockKind.other: Icons.notes,
};

IconData blockKindIcon(BlockKind k) => _kindIcons[k]!;

/// Un bloc de séance : ses exercices (réordonnables) et un champ de saisie rapide.
///
/// Dans le champ, `10x400 r1'` puis « + » (ou le bouton) ajoute l'exercice ; on peut en saisir
/// plusieurs d'un coup (`10x400 r1' 3x300 r1'`, ou un par ligne). L'aperçu montre en direct
/// comment le texte est compris.
class BlockCard extends StatefulWidget {
  const BlockCard({
    super.key,
    required this.block,
    required this.index,
    required this.count,
    required this.onChanged,
    required this.onDelete,
    required this.onDuplicate,
    required this.onMove,
  });

  final BlockDraft block;
  final int index;
  final int count;

  /// Le contenu du brouillon a changé (le parent se redessine et marque « modifié »).
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final ValueChanged<int> onMove;

  @override
  State<BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends State<BlockCard> {
  final _input = TextEditingController();
  late final FocusNode _focus = FocusNode()..addListener(() => setState(() {}));

  BlockDraft get _b => widget.block;

  @override
  void dispose() {
    _focus.dispose();
    _input.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  void _add() {
    final items = parseNotation(_input.text);
    if (items.isEmpty) return;
    _b.items.addAll(items);
    _input.clear();
    _changed();
  }

  void _insert(String text) {
    final value = _input.value;
    final t = value.text;
    final start = value.selection.isValid ? value.selection.start : t.length;
    final end = value.selection.isValid ? value.selection.end : t.length;
    _input.value = TextEditingValue(
      text: t.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    setState(() {});
  }

  Future<void> _editItem(int i) async {
    final controller = TextEditingController(text: _b.items[i].toNotation());
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final preview = parseNotation(controller.text);
          return AlertDialog(
            title: const Text('Modifier l’exercice'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('edit-item'),
                  controller: controller,
                  autofocus: true,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(hintText: "10x400 r1'"),
                ),
                const SizedBox(height: 12),
                for (final p in preview) Text(p.format()),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    final parsed = parseNotation(result);
    if (parsed.isEmpty) return;
    _b.items.replaceRange(i, i + 1, parsed);
    _changed();
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _b.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nom du bloc'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: _b.kind.label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result == null) return;
    _b.title = result;
    _changed();
  }

  void _onMenu(String v) {
    switch (v) {
      case 'up':
        widget.onMove(-1);
      case 'down':
        widget.onMove(1);
      case 'dup':
        widget.onDuplicate();
      case 'rename':
        _rename();
      case 'del':
        widget.onDelete();
      default:
        if (v.startsWith('k:')) {
          _b.kind = BlockKind.parse(v.substring(2));
          _changed();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final volume = totalVolumeM(_b.items);
    final preview = parseNotation(_input.text);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(blockKindIcon(_b.kind), size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(_b.heading, style: theme.textTheme.titleSmall)),
                if (volume > 0)
                  Text(formatDistance(volume),
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                PopupMenuButton<String>(
                  tooltip: 'Options du bloc',
                  onSelected: _onMenu,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Renommer')),
                    for (final k in BlockKind.values)
                      if (k != _b.kind) PopupMenuItem(value: 'k:${k.name}', child: Text('Devient : ${k.label}')),
                    const PopupMenuDivider(),
                    if (widget.index > 0) const PopupMenuItem(value: 'up', child: Text('Monter')),
                    if (widget.index < widget.count - 1) const PopupMenuItem(value: 'down', child: Text('Descendre')),
                    const PopupMenuItem(value: 'dup', child: Text('Dupliquer')),
                    const PopupMenuItem(value: 'del', child: Text('Supprimer le bloc')),
                  ],
                ),
              ],
            ),
            if (_b.items.isNotEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _b.items.length,
                onReorderItem: (from, to) {
                  _b.items.insert(to, _b.items.removeAt(from));
                  _changed();
                },
                itemBuilder: (context, i) {
                  final item = _b.items[i];
                  return ListTile(
                    key: ObjectKey(item),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    minLeadingWidth: 0,
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: Icon(Icons.drag_indicator, color: theme.colorScheme.outline),
                    ),
                    title: Text(
                      item.format(),
                      style: item.hasEffort
                          ? theme.textTheme.bodyLarge
                          : theme.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic),
                    ),
                    trailing: IconButton(
                      tooltip: 'Supprimer l’exercice',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        _b.items.removeAt(i);
                        _changed();
                      },
                    ),
                    onTap: () => _editItem(i),
                  );
                },
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: TextField(
                key: Key('quick-input-${widget.index}'),
                controller: _input,
                focusNode: _focus,
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: "Ajouter : 10x400 r1'  3x300 r1'",
                  suffixIcon: IconButton(
                    key: Key('quick-add-${widget.index}'),
                    tooltip: 'Ajouter',
                    icon: const Icon(Icons.add_circle),
                    color: theme.colorScheme.primary,
                    onPressed: preview.isEmpty ? null : _add,
                  ),
                ),
              ),
            ),
            if (preview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in preview)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        label: Text(
                          p.format(),
                          style: TextStyle(
                            fontStyle: p.hasEffort ? null : FontStyle.italic,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_focus.hasFocus)
              // ExcludeFocus : toucher un raccourci ne doit pas retirer le focus du champ
              // (sur mobile, cela fermerait le clavier).
              ExcludeFocus(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: Row(
                    children: [
                      for (final s in const ['x', 'r', "'", '"', '@', 'm', 'km'])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(s, style: const TextStyle(fontWeight: FontWeight.w600)),
                            onPressed: () => _insert(s),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
