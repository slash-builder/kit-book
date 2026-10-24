// SaveStatusChip: "Saving..." / "Saved" / "Not saved".
//
// Candidate evidence: ONE app (notepad's `SaveStatus`, a 28 dp text line). No
// other demo app asked for it.

import 'package:flutter/material.dart';

/// Where a document is in its save cycle.
enum SaveStatus { idle, saving, saved, notSaved }

/// A small chip showing a [SaveStatus]. [SaveStatus.idle] renders nothing and
/// takes no space (nothing is open, so there is nothing to say).
///
/// The state is carried by an icon and a word, with colour only as support. The
/// accessible label is "Save status: Saved". Only [SaveStatus.notSaved] is a
/// live region: a failure interrupts, a routine autosave does not chatter.
class SaveStatusChip extends StatelessWidget {
  const SaveStatusChip({super.key, required this.status});

  final SaveStatus status;

  /// The visible word for [status]; empty for [SaveStatus.idle].
  static String labelFor(SaveStatus status) => switch (status) {
        SaveStatus.idle => '',
        SaveStatus.saving => 'Saving...',
        SaveStatus.saved => 'Saved',
        SaveStatus.notSaved => 'Not saved',
      };

  @override
  Widget build(BuildContext context) {
    if (status == SaveStatus.idle) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final label = labelFor(status);
    final (icon, background, foreground) = switch (status) {
      SaveStatus.saving => (
          Icons.sync,
          scheme.surfaceContainerHighest,
          scheme.onSurface
        ),
      SaveStatus.saved => (
          Icons.check,
          scheme.surfaceContainerHighest,
          scheme.onSurface
        ),
      SaveStatus.notSaved => (
          Icons.error_outline,
          scheme.errorContainer,
          scheme.onErrorContainer
        ),
      SaveStatus.idle => (
          Icons.circle,
          scheme.surface,
          scheme.onSurface
        ), // unreachable
    };
    return Semantics(
      container: true,
      label: 'Save status: $label',
      liveRegion: status == SaveStatus.notSaved,
      excludeSemantics: true,
      child: Chip(
        avatar: Icon(icon, color: foreground),
        label: Text(label),
        labelStyle: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: foreground),
        backgroundColor: background,
        side: BorderSide(color: foreground),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
