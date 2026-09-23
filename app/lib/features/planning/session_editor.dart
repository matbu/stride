import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/notation.dart';
import '../../core/session_icons.dart';
import '../../core/theme.dart';
import '../../data/drafts.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../../data/session_actions.dart';
import '../common.dart';
import 'block_card.dart';

Future<void> openSessionEditor(BuildContext context, SessionDraft draft) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => SessionEditorScreen(draft: draft)),
  );
}

/// Contenu par défaut d'un bloc échauffement/retour au calme fraîchement ajouté — un point de
/// départ courant, à modifier ou effacer librement (ce sont des exercices comme les autres,
/// donc enregistrés tels quels s'ils restent).
BlockDraft _defaultBlock(BlockKind kind) => switch (kind) {
      BlockKind.warmup => BlockDraft(kind: kind, items: const [BlockItem(durationS: 20 * 60)]),
      BlockKind.cooldown => BlockDraft(kind: kind, items: const [BlockItem(note: 'Étirements')]),
      BlockKind.main || BlockKind.other => BlockDraft(kind: kind),
    };

/// Brouillon d'une nouvelle séance : trois blocs, échauffement et retour au calme pré-remplis
/// (voir `_defaultBlock`) — le corps de séance reste vide.
SessionDraft newSessionDraft({DateTime? date, String? groupId, bool template = false}) => SessionDraft(
      isTemplate: template,
      date: template ? null : isoDate(date ?? dateOnly(DateTime.now())),
      groupIds: {?groupId},
      blocks: [
        _defaultBlock(BlockKind.warmup),
        _defaultBlock(BlockKind.main),
        _defaultBlock(BlockKind.cooldown),
      ],
    );

const _durations = [30, 45, 60, 75, 90, 120];

/// Éditeur d'une séance ou d'un modèle : infos (type, titre, groupes, jour) puis blocs.
class SessionEditorScreen extends ConsumerStatefulWidget {
  const SessionEditorScreen({super.key, required this.draft});
  final SessionDraft draft;

  @override
  ConsumerState<SessionEditorScreen> createState() => _SessionEditorScreenState();
}

class _SessionEditorScreenState extends ConsumerState<SessionEditorScreen> {
  late final SessionDraft _d = widget.draft;
  late final TextEditingController _title = TextEditingController(text: _d.title);
  late final TextEditingController _notes = TextEditingController(text: _d.description);

  /// Une séance existante charge ses blocs depuis la base ; une nouvelle a déjà les siens.
  late bool _blocksLoaded = _d.id == null;
  bool _dirty = false;
  bool _busy = false;

  bool get _editing => _d.id != null;
  bool get _valid =>
      _blocksLoaded &&
      _d.typeId != null &&
      _title.text.trim().isNotEmpty &&
      (_d.isTemplate || _d.groupIds.isNotEmpty);

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _touch() => setState(() => _dirty = true);

  BlockDraft? get _mainBlock {
    for (final b in _d.blocks) {
      if (b.kind == BlockKind.main) return b;
    }
    return null;
  }

  /// Suggestion de remplissage du corps de séance à partir du titre, si celui-ci ressemble à de
  /// la saisie rapide (« 10x400 r1' »). On ne l'applique jamais silencieusement (un titre peut
  /// contenir des chiffres sans être une notation, ex. « 10 × 400 m ») : le coach valide.
  List<BlockItem>? _titleSuggestion;

  void _updateTitleSuggestion(String text) {
    final main = _mainBlock;
    // Le marqueur `x`/`X` entre deux chiffres est le signal fort de la notation (par opposition
    // à un titre qui contient juste des nombres, ex. le signe « × » n'est pas un « x »).
    final looksLikeNotation = RegExp(r'\d\s*[xX]\s*\d').hasMatch(text);
    List<BlockItem>? suggestion;
    if (main != null && main.items.isEmpty && looksLikeNotation) {
      final parsed = parseNotation(text);
      if (parsed.any((i) => i.hasEffort)) suggestion = parsed;
    }
    if (suggestion != _titleSuggestion) setState(() => _titleSuggestion = suggestion);
  }

  void _applyTitleSuggestion() {
    final suggestion = _titleSuggestion;
    final main = _mainBlock;
    if (suggestion == null || main == null) return;
    setState(() {
      main.items = suggestion;
      _titleSuggestion = null;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final clubId = ref.read(clubIdProvider);
    if (clubId == null || !_valid) return;
    _d.title = _title.text.trim();
    _d.description = _notes.text.trim();
    // Les blocs laissés vides ne sont pas enregistrés.
    _d.blocks.removeWhere((b) => b.items.isEmpty && b.title.isEmpty && b.notes.isEmpty);
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      await ref.read(sessionActionsProvider).save(_d, clubId: clubId);
      return true;
    });
    if (!mounted) return;
    if (ok == true) {
      setState(() => _dirty = false);
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abandonner les modifications ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuer')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abandonner')),
        ],
      ),
    );
    return leave == true;
  }

  /// Retour bloqué par des modifications non enregistrées : on demande, puis on quitte.
  Future<void> _leaveAfterConfirm() async {
    final leave = await _confirmDiscard();
    if (!mounted || !leave) return;
    setState(() => _dirty = false);
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_d.isTemplate ? 'Supprimer le modèle ?' : 'Supprimer la séance ?'),
        content: Text('« ${_d.title} » sera supprimé${_d.isTemplate ? '' : 'e'} pour tout le monde.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(sessionActionsProvider).delete(_d.id!);
    if (!mounted) return;
    setState(() => _dirty = false);
    Navigator.pop(context);
  }

  Future<void> _saveAsTemplate() async {
    final clubId = ref.read(clubIdProvider);
    if (clubId == null || _d.typeId == null || _title.text.trim().isEmpty) return;
    final copy = SessionDraft(
      isTemplate: true,
      typeId: _d.typeId,
      title: _title.text.trim(),
      description: _d.description,
      durationMin: _d.durationMin,
      blocks: [
        for (final b in _d.blocks)
          if (b.items.isNotEmpty || b.title.isNotEmpty) b.copy(freshId: true),
      ],
    );
    await guarded(context, () => ref.read(sessionActionsProvider).save(copy, clubId: clubId));
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Ajouté à la bibliothèque')));
    }
  }

  void _addBlock(BlockKind kind) {
    final block = _defaultBlock(kind);
    setState(() {
      switch (kind) {
        case BlockKind.warmup:
          _d.blocks.insert(0, block);
        case BlockKind.cooldown:
          _d.blocks.add(block);
        case BlockKind.main || BlockKind.other:
          final cooldown = _d.blocks.indexWhere((b) => b.kind == BlockKind.cooldown);
          _d.blocks.insert(cooldown >= 0 ? cooldown : _d.blocks.length, block);
      }
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_blocksLoaded) {
      final loaded = ref.watch(blocksForSessionProvider(_d.id!));
      if (loaded.hasValue) {
        _d.blocks
          ..clear()
          ..addAll(loaded.requireValue.map(BlockDraft.from));
        if (_d.blocks.isEmpty) _d.blocks.add(BlockDraft(kind: BlockKind.main));
        _blocksLoaded = true;
      }
    }

    // Le club est lu à l'enregistrement (ref.read) : on le suit ici pour que le flux reste actif.
    ref.watch(clubIdProvider);
    final types = ref.watch(sessionTypesProvider).value ?? const <SessionType>[];
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveAfterConfirm();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_d.isTemplate
              ? (_editing ? 'Modifier le modèle' : 'Nouveau modèle')
              : (_editing ? 'Modifier la séance' : 'Nouvelle séance')),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) => v == 'template' ? _saveAsTemplate() : _delete(),
              itemBuilder: (_) => [
                if (!_d.isTemplate)
                  const PopupMenuItem(value: 'template', child: Text('Enregistrer comme modèle')),
                if (_editing) const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              key: const Key('session-save'),
              onPressed: (_busy || !_valid) ? null : _save,
              child: Text(_editing ? 'Enregistrer' : (_d.isTemplate ? 'Créer le modèle' : 'Créer la séance')),
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Text('Type', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in types)
                      ChoiceChip(
                        key: Key('type-${t.name}'),
                        avatar: Icon(sessionIcon(t.icon),
                            size: 18, color: _d.typeId == t.id ? onColor(t.color) : t.color),
                        label: Text(t.name),
                        selected: _d.typeId == t.id,
                        selectedColor: t.color,
                        labelStyle: TextStyle(color: _d.typeId == t.id ? onColor(t.color) : null),
                        showCheckmark: false,
                        onSelected: (_) {
                          _d.typeId = t.id;
                          _touch();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('session-title'),
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Titre', hintText: 'ex. 10 × 400 m'),
                  onChanged: (v) {
                    _touch();
                    _updateTitleSuggestion(v);
                  },
                ),
                if (_titleSuggestion != null) ...[
                  const SizedBox(height: 8),
                  ActionChip(
                    key: const Key('title-autofill-suggestion'),
                    avatar: const Icon(Icons.auto_awesome, size: 16),
                    label: Text(
                      'Remplir le corps de séance (${_titleSuggestion!.length} '
                      'exercice${_titleSuggestion!.length > 1 ? 's' : ''} détecté'
                      '${_titleSuggestion!.length > 1 ? 's' : ''})',
                    ),
                    onPressed: _applyTitleSuggestion,
                  ),
                ],
                if (!_d.isTemplate) ...[
                  const SizedBox(height: 16),
                  Text(_editing ? 'Groupe' : 'Groupe(s)', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  if (groups.isEmpty)
                    Text(
                      'Aucun groupe pour le moment. Crée-en un dans l’onglet Club.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final g in groups)
                          FilterChip(
                            key: Key('group-${g.name}'),
                            label: Text(g.name),
                            selected: _d.groupIds.contains(g.id),
                            onSelected: (on) {
                              if (_editing) {
                                _d.groupIds
                                  ..clear()
                                  ..add(g.id);
                              } else if (on) {
                                _d.groupIds.add(g.id);
                              } else {
                                _d.groupIds.remove(g.id);
                              }
                              _touch();
                            },
                          ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                          icon: const Icon(Icons.event),
                          label: Text(longDayLabel(parseIsoDate(_d.date!)), overflow: TextOverflow.ellipsis),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: parseIsoDate(_d.date!),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) {
                              _d.date = isoDate(d);
                              _touch();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                        icon: const Icon(Icons.schedule),
                        label: Text(_d.startTime ?? 'Heure'),
                        onPressed: () async {
                          final initial = _d.startTime == null
                              ? const TimeOfDay(hour: 18, minute: 30)
                              : TimeOfDay(
                                  hour: int.parse(_d.startTime!.substring(0, 2)),
                                  minute: int.parse(_d.startTime!.substring(3, 5)),
                                );
                          final t = await showTimePicker(context: context, initialTime: initial);
                          if (t != null) {
                            _d.startTime =
                                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                            _touch();
                          }
                        },
                      ),
                      if (_d.startTime != null)
                        IconButton(
                          tooltip: 'Retirer l’heure',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _d.startTime = null;
                            _touch();
                          },
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Text('Durée', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in _durations)
                      ChoiceChip(
                        label: Text('$m min'),
                        selected: _d.durationMin == m,
                        onSelected: (on) {
                          _d.durationMin = on ? m : null;
                          _touch();
                        },
                      ),
                  ],
                ),
                const SectionHeader('Contenu'),
                if (!_blocksLoaded)
                  const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                else ...[
                  for (var i = 0; i < _d.blocks.length; i++) ...[
                    BlockCard(
                      key: ValueKey(_d.blocks[i].id),
                      block: _d.blocks[i],
                      index: i,
                      count: _d.blocks.length,
                      onChanged: _touch,
                      onDelete: () {
                        _d.blocks.removeAt(i);
                        _touch();
                      },
                      onDuplicate: () {
                        _d.blocks.insert(i + 1, _d.blocks[i].copy(freshId: true));
                        _touch();
                      },
                      onMove: (delta) {
                        final to = i + delta;
                        if (to < 0 || to >= _d.blocks.length) return;
                        _d.blocks.insert(to, _d.blocks.removeAt(i));
                        _touch();
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final k in BlockKind.values)
                        ActionChip(
                          key: Key('add-block-${k.name}'),
                          avatar: Icon(blockKindIcon(k), size: 18),
                          label: Text(k.label),
                          onPressed: () => _addBlock(k),
                        ),
                    ],
                  ),
                  if (_d.volumeM > 0) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Volume d’effort : ${formatDistance(_d.volumeM)}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ],
                const SectionHeader('Notes'),
                TextField(
                  key: const Key('session-notes'),
                  controller: _notes,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Ressenti, ajustements, consignes… avant ou après la séance.',
                  ),
                  onChanged: (_) => _touch(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
