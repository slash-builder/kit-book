import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:interface_candidates/interface_candidates.dart';

import '../logic/note.dart';
import '../logic/settings.dart';
import 'notes_controller.dart';
import 'notes_list.dart';

class NotepadScreen extends StatefulWidget {
  const NotepadScreen({super.key, required this.controller});
  final NotesController controller;

  @override
  State<NotepadScreen> createState() => _NotepadScreenState();
}

class _NotepadScreenState extends State<NotepadScreen> {
  NotesController get c => widget.controller;

  /// Narrow layouts show the list OR the editor (PageScaffold.masterDetail); wide ones show both and ignore this.
  bool _showEditor = false;

  void _create() {
    c.create();
    setState(() => _showEditor = true);
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppContextScope.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final save = _saveStatus();
        final peers = c.peers;
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
            rows: [for (final n in c.notes) NoteRowData(id: n.id, title: n.title, preview: _preview(n))],
            selectedId: c.selectedId,
            disabledRows: [for (final d in c.damaged) d.fileName],
            onSelect: (id) {
              c.select(id);
              setState(() => _showEditor = true);
            },
            onNew: _create,
            onRename: _rename,
            onDelete: _confirmDelete,
          ),
          detail: c.selected == null ? _empty() : _editor(c.selected!),
          footer: peers == null && save == SaveStatus.idle
              ? null
              : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (peers != null)
                    PeersIndicator.forHandle(peers.handle, extra: peers.sync.pending > 0 ? 'Syncing ${peers.sync.pending}...' : null),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: SaveStatusChip(status: save)),
                ]),
        );
      },
    );
  }

  String _preview(Note n) {
    final line = n.body.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    return line.isEmpty ? 'Empty' : line;
  }

  // An Interface Kit "empty state" component would replace this.
  Widget _empty() => EmptyState(
        key: const ValueKey('empty-state'),
        title: 'No notes yet',
        action: CandidateAction(label: 'Create a note', onPressed: _create),
      );

  Widget _editor(Note n) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(alignment: Alignment.centerLeft, child: Text(n.title, key: const ValueKey('editor-title'), style: Theme.of(context).textTheme.headlineSmall)),
        ),
        Expanded(child: _NoteEditor(key: ValueKey('editor-${n.id}-${c.remoteRevision(n.id)}'), note: n, fontSize: c.settings.fontSize, onChanged: (t) => c.edit(n.id, t))),
      ]);

  SaveStatus _saveStatus() => c.saveFailed
      ? SaveStatus.notSaved
      : (c.hasUnsavedChanges ? SaveStatus.saving : (c.selected == null ? SaveStatus.idle : SaveStatus.saved));

  Future<void> _rename(String id) async {
    final n = c.notes.firstWhere((n) => n.id == id);
    final result = await promptDialog(context,
        title: 'Rename note', confirmLabel: 'Rename', initial: n.title, fieldKey: const ValueKey('rename-field'), confirmKey: const ValueKey('rename-ok'));
    if (result != null) c.rename(id, result);
  }

  Future<void> _confirmDelete(String id) async {
    final n = c.notes.firstWhere((n) => n.id == id);
    final ok = await confirmDialog(context,
        title: 'Delete "${n.title}"?', message: 'This cannot be undone.', confirmLabel: 'Delete', destructive: true, confirmKey: const ValueKey('delete-ok'));
    if (ok) c.delete(id);
  }
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({super.key, required this.note, required this.fontSize, required this.onChanged});
  final Note note;
  final double fontSize;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController text = TextEditingController(text: widget.note.body);

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
