import 'package:application_kit_flutter/application_kit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:interface_candidates/interface_candidates.dart';

import '../logic/settings.dart';
import 'history_sheet.dart';
import 'notes_controller.dart';
import 'notes_list.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.controller});
  final NotesController controller;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  NotesController get c => widget.controller;

  /// Narrow layouts show the list OR the editor (PageScaffold.masterDetail); wide ones show both and ignore this.
  bool _showEditor = false;

  Future<void> _create() async {
    await c.create();
    if (mounted) setState(() => _showEditor = true);
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppContextScope.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final save = _saveStatus();
        final peers = c.peers;
        final stats = c.stats;
        return PageScaffold.masterDetail(
          title: ctx.manifest.name,
          actions: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: ModeBadge.forContext(ctx, key: const ValueKey('mode-chip'))),
            IconButton(key: const ValueKey('font-smaller'), tooltip: 'Smaller text', icon: const Icon(Icons.text_decrease), onPressed: () => c.changeFont(-Settings.step)),
            Center(child: Text('${c.settings.fontSize.round()}', key: const ValueKey('font-size'))),
            IconButton(key: const ValueKey('font-larger'), tooltip: 'Larger text', icon: const Icon(Icons.text_increase), onPressed: () => c.changeFont(Settings.step)),
          ],
          banner: NotesBanner.forContext(ctx, key: const ValueKey('notice'), dismissible: true),
          masterWidth: 280,
          masterLabel: 'Notes',
          detailLabel: 'Editor',
          showDetail: _showEditor,
          onDetailBack: () => setState(() => _showEditor = false),
          master: NotesList(
            rows: [for (final n in c.notes) NoteRowData(id: n.id, title: n.title, preview: n.preview.isEmpty ? 'Empty' : n.preview)],
            selectedId: c.selectedId,
            disabledRows: const [],
            onSelect: (id) async {
              await c.select(id);
              if (mounted) setState(() => _showEditor = true);
            },
            onNew: _create,
            onRename: _rename,
            onDelete: _confirmDelete,
          ),
          detail: c.selectedId == null || c.selected == null ? _empty() : _editor(c.selectedId!),
          footer: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (peers != null) PeersIndicator.forHandle(peers.handle, extra: peers.sync.pending > 0 ? 'Syncing ${peers.sync.pending}...' : null),
            if (stats != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Rust core: ${stats.noteCount} notes, ${stats.blockCount} blocks, shares this app\'s context (instance ${stats.instance})',
                  key: const ValueKey('core-line'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: SaveStatusChip(status: save)),
          ]),
        );
      },
    );
  }

  // An Interface Kit "empty state" component would replace this.
  Widget _empty() => EmptyState(
        key: const ValueKey('empty-state'),
        title: 'No notes yet',
        action: CandidateAction(label: 'Create a note', onPressed: _create),
      );

  Widget _editor(String id) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            Expanded(child: Text(c.draftTitle, key: const ValueKey('editor-title'), style: Theme.of(context).textTheme.headlineSmall)),
            IconButton(key: const ValueKey('history'), tooltip: 'Version history', icon: const Icon(Icons.history), onPressed: () => _history(id)),
          ]),
        ),
        Expanded(
          child: _NoteEditor(
            key: ValueKey('editor-$id-${c.remoteRevision(id)}'),
            initial: c.draftBody,
            fontSize: c.settings.fontSize,
            onChanged: (t) => c.edit(id, t),
          ),
        ),
      ]);

  SaveStatus _saveStatus() => c.saveFailed
      ? SaveStatus.notSaved
      : (c.hasUnsavedChanges ? SaveStatus.saving : (c.selectedId == null ? SaveStatus.idle : SaveStatus.saved));

  Future<void> _history(String id) async {
    await c.flush(); // the sheet lists what is saved, so save what is typed first
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HistorySheet(controller: c, noteId: id),
    );
  }

  Future<void> _rename(String id) async {
    final n = c.notes.firstWhere((n) => n.id == id);
    final result = await promptDialog(context,
        title: 'Rename note', confirmLabel: 'Rename', initial: n.title, fieldKey: const ValueKey('rename-field'), confirmKey: const ValueKey('rename-ok'));
    if (result != null) await c.rename(id, result);
  }

  Future<void> _confirmDelete(String id) async {
    final n = c.notes.firstWhere((n) => n.id == id);
    final ok = await confirmDialog(context,
        title: 'Delete "${n.title}"?',
        message: 'The note leaves the list. Its versions stay in the store.',
        confirmLabel: 'Delete',
        destructive: true,
        confirmKey: const ValueKey('delete-ok'));
    if (ok) await c.delete(id);
  }
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({super.key, required this.initial, required this.fontSize, required this.onChanged});
  final String initial;
  final double fontSize;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          key: const ValueKey('editor'),
          controller: text,
          autofocus: true,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(fontSize: widget.fontSize),
          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Start typing'),
          onChanged: widget.onChanged,
        ),
      );
}
