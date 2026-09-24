import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../../data/session_actions.dart';
import '../common.dart';
import 'session_badge.dart';

/// Place un modèle sur un jour, pour un ou plusieurs groupes. Chaque groupe reçoit sa propre
/// copie (séance + blocs) : modifier le modèle plus tard ne change pas les séances placées.
Future<void> showPlaceSheet(
  BuildContext context, {
  required Template template,
  DateTime? date,
  String? groupId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PlaceForm(template: template, date: date, groupId: groupId),
  );
}

/// Choix d'un modèle dans la bibliothèque. Renvoie null si on ferme sans choisir.
Future<Template?> showTemplatePicker(BuildContext context) {
  return showModalBottomSheet<Template>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _TemplatePicker(),
  );
}

class _TemplatePicker extends ConsumerWidget {
  const _TemplatePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider).value ?? const <Template>[];
    final types = {for (final t in ref.watch(sessionTypesProvider).value ?? const <SessionType>[]) t.id: t};
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Choisir un modèle', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (templates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'La bibliothèque est vide. Crée un modèle dans l’onglet Modèles, '
                'ou enregistre une séance comme modèle.',
              ),
            ),
          for (final t in templates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  key: Key('pick-${t.title}'),
                  title: Text(t.title),
                  subtitle: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TypeBadge(type: types[t.typeId]),
                    ),
                  ),
                  onTap: () => Navigator.pop(context, t),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaceForm extends ConsumerStatefulWidget {
  const _PlaceForm({required this.template, this.date, this.groupId});
  final Template template;
  final DateTime? date;
  final String? groupId;

  @override
  ConsumerState<_PlaceForm> createState() => _PlaceFormState();
}

class _PlaceFormState extends ConsumerState<_PlaceForm> {
  late DateTime _date = widget.date ?? dateOnly(DateTime.now());
  late final Set<String> _groups = {?widget.groupId};
  String? _time; // HH:mm
  bool _busy = false;

  Future<void> _place() async {
    final clubId = ref.read(clubIdProvider);
    if (clubId == null || _groups.isEmpty) return;
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      await ref.read(sessionActionsProvider).place(
            templateId: widget.template.id,
            clubId: clubId,
            groupIds: _groups,
            date: isoDate(_date),
            startTime: _time,
          );
      return true;
    });
    if (!mounted) return;
    if (ok == true) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.watch(clubIdProvider); // lu au moment de placer (ref.read) : garde le flux actif
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Placer « ${widget.template.title} »', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Text('Groupe(s)', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            Text('Aucun groupe. Crée-en un dans l’onglet Club.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in groups)
                  FilterChip(
                    key: Key('place-group-${g.name}'),
                    label: Text(g.name),
                    selected: _groups.contains(g.id),
                    onSelected: (on) => setState(() => on ? _groups.add(g.id) : _groups.remove(g.id)),
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
                  label: Text(longDayLabel(_date), overflow: TextOverflow.ellipsis),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.schedule),
                label: Text(_time ?? 'Heure'),
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 18, minute: 30),
                  );
                  if (t != null) {
                    setState(() => _time =
                        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('place-confirm'),
            onPressed: (_busy || _groups.isEmpty) ? null : _place,
            child: const Text('Placer la séance'),
          ),
        ],
      ),
    );
  }
}
