import 'package:flutter/material.dart';
import 'package:interface_candidates/interface_candidates.dart';

import '../core/notes_core.dart';
import 'notes_controller.dart';

/// The version history of one note: every version this copy knows of, newest first. A version whose blocks were never synced
/// here is listed but cannot be previewed or restored. Restoring writes one new version that points at the old version's
/// existing blocks (no body is copied), which is what content addressing buys.
class HistorySheet extends StatefulWidget {
  const HistorySheet({super.key, required this.controller, required this.noteId});
  final NotesController controller;
  final String noteId;

  @override
  State<HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<HistorySheet> {
  late Future<List<VersionInfo>> _versions = widget.controller.history(widget.noteId);

  void _reload() => setState(() => _versions = widget.controller.history(widget.noteId));

  String _when(int atMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: true).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _size(int n) => n < 1024 ? '$n B' : (n < 1024 * 1024 ? '${(n / 1024).toStringAsFixed(1)} KB' : '${(n / 1048576).toStringAsFixed(1)} MB');

  Future<void> _preview(VersionInfo v) async {
    final n = await widget.controller.preview(widget.noteId, v.manifest);
    if (!mounted) return;
    final shown = n.body.length > 4000 ? '${n.body.substring(0, 4000)}\n...' : n.body;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(n.title),
        content: SingleChildScrollView(child: SelectableText(shown.isEmpty ? '(empty)' : shown, key: const ValueKey('preview-body'))),
        actions: [TextButton(key: const ValueKey('preview-close'), onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _restore(VersionInfo v) async {
    final ok = await widget.controller.restore(widget.noteId, v.manifest);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Version history', key: const ValueKey('history-title'), style: Theme.of(context).textTheme.titleLarge),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Each save is a version. Restoring one adds a new version; nothing is deleted.'),
          ),
          Flexible(
            child: FutureBuilder<List<VersionInfo>>(
              future: _versions,
              builder: (context, snap) {
                if (snap.hasError) return Padding(padding: const EdgeInsets.all(16), child: Text('Could not read the history: ${snap.error}'));
                final rows = snap.data;
                if (rows == null) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                return ListView(shrinkWrap: true, children: [
                  for (final v in rows)
                    ListTile(
                      key: ValueKey('version-${v.manifest.substring(0, 8)}'),
                      title: Text(_when(v.atMs)),
                      subtitle: Text([
                        v.deleted ? 'deleted' : _size(v.len),
                        'on ${v.by}',
                        if (v.parents.length > 1) 'merge',
                        if (!v.available) 'not on this copy',
                      ].join(' - ')),
                      leading: v.isHead ? const Chip(key: ValueKey('current-chip'), label: Text('current')) : null,
                      onTap: v.available && !v.deleted ? () => _preview(v) : null,
                      trailing: v.isHead
                          ? null
                          : TextButton(
                              key: ValueKey('restore-${v.manifest.substring(0, 8)}'),
                              onPressed: v.available ? () => _restore(v) : null,
                              child: const Text('Restore'),
                            ),
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// "3 minutes ago" for the footer; re-exported so the screen has one import.
String ago(int atMs) => relativeTime(DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: true));
