import 'package:flutter/material.dart';

/// One row of the list: what to show, with an opaque [id] handed back in the callbacks.
class NoteRowData {
  const NoteRowData({required this.id, required this.title, required this.preview});
  final String id, title, preview;
}

enum _RowAction { rename, delete }

// Interface Kit candidate: a titled list with a "new" button, a selected row, an overflow menu per row and rows that are
// shown but disabled (files that could not be read). Knows nothing about notes: the app maps its data to [NoteRowData].
class NotesList extends StatelessWidget {
  const NotesList({
    super.key,
    required this.rows,
    required this.selectedId,
    required this.disabledRows,
    required this.onSelect,
    required this.onNew,
    required this.onRename,
    required this.onDelete,
  });

  final List<NoteRowData> rows;
  final String? selectedId;

  /// Names of things that could not be read: shown after the rows, greyed, with a warning icon.
  final List<String> disabledRows;
  final ValueChanged<String> onSelect, onRename, onDelete;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => Column(children: [
        ListTile(
          title: Text('Notes (${rows.length})', style: Theme.of(context).textTheme.titleMedium),
          trailing: IconButton(key: const ValueKey('new-note'), tooltip: 'New note', icon: const Icon(Icons.add), onPressed: onNew),
        ),
        Expanded(
          child: ListView(children: [
            for (final r in rows)
              ListTile(
                key: ValueKey('note-${r.id}'),
                selected: r.id == selectedId,
                title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(r.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => onSelect(r.id),
                trailing: PopupMenuButton<_RowAction>(
                  key: ValueKey('note-menu-${r.id}'),
                  onSelected: (a) => a == _RowAction.rename ? onRename(r.id) : onDelete(r.id),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: _RowAction.rename, child: Text('Rename')),
                    PopupMenuItem(value: _RowAction.delete, child: Text('Delete')),
                  ],
                ),
              ),
            for (final name in disabledRows)
              ListTile(
                key: ValueKey('damaged-$name'),
                enabled: false,
                leading: const Icon(Icons.warning_amber),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Could not be read. Left untouched.'),
              ),
          ]),
        ),
      ]);
}
