import 'package:uuid/uuid.dart';

import '../core/notation.dart';
import 'models.dart';

const _uuid = Uuid();

/// Bloc en cours d'édition (copie modifiable de la base).
class BlockDraft {
  BlockDraft({
    String? id,
    required this.kind,
    this.title = '',
    this.notes = '',
    List<BlockItem>? items,
  })  : id = id ?? _uuid.v4(),
        items = items ?? [];

  factory BlockDraft.from(SessionBlock b) => BlockDraft(
        id: b.id,
        kind: b.kind,
        title: b.title,
        notes: b.notes,
        items: [...b.items],
      );

  final String id;
  BlockKind kind;
  String title;
  String notes;
  List<BlockItem> items;

  String get heading => title.isNotEmpty ? title : kind.label;

  /// Copie indépendante ; `freshId` pour un nouveau bloc (duplication, placement d'un modèle).
  BlockDraft copy({bool freshId = false}) => BlockDraft(
        id: freshId ? null : id,
        kind: kind,
        title: title,
        notes: notes,
        items: [...items],
      );
}

/// Séance en cours d'édition : soit un modèle de la bibliothèque, soit une séance à placer.
class SessionDraft {
  SessionDraft({
    this.id,
    this.isTemplate = false,
    this.typeId,
    this.title = '',
    this.description = '',
    Set<String>? groupIds,
    this.date,
    this.startTime,
    this.durationMin,
    this.templateId,
    List<BlockDraft>? blocks,
  })  : groupIds = groupIds ?? {},
        blocks = blocks ?? [BlockDraft(kind: BlockKind.main)];

  factory SessionDraft.fromPlanned(PlannedSession s) => SessionDraft(
        id: s.id,
        typeId: s.typeId,
        title: s.title,
        description: s.description,
        groupIds: {s.groupId},
        date: s.date,
        startTime: s.startTime?.substring(0, 5),
        durationMin: s.durationMin,
        blocks: [],
      );

  factory SessionDraft.fromTemplate(Template t) => SessionDraft(
        id: t.id,
        isTemplate: true,
        typeId: t.typeId,
        title: t.title,
        description: t.description,
        durationMin: t.durationMin,
        blocks: [],
      );

  /// Existe déjà en base (édition) ; null pour une création.
  final String? id;
  final bool isTemplate;
  String? typeId;
  String title;
  String description;

  /// Groupes cibles. Une création avec plusieurs groupes crée une séance par groupe.
  final Set<String> groupIds;

  /// `yyyy-MM-dd`
  String? date;

  /// `HH:mm`
  String? startTime;
  int? durationMin;

  /// Modèle d'origine, si la séance en est issue.
  String? templateId;
  final List<BlockDraft> blocks;

  int get volumeM => totalVolumeM(blocks.expand((b) => b.items));

  bool get hasContent => blocks.any((b) => b.items.isNotEmpty);
}
