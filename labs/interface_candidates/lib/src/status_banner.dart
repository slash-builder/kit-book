// StatusBanner: a full-width inline notice.
//
// Candidate evidence: 5 of the 6 demo apps (all but the calculator) wanted one
// and 4 hand-built something: notepad and minesweeper (damaged-file notice),
// launcher (`_Banner`), render-queue (venue banner and `_OrphanBanner`).
// The larger app wraps its own banner widget (239 uses in 30 files). The companion's NotesBanner
// is this widget plus a list of notes; see README.

import 'package:flutter/material.dart';

import 'candidate_action.dart';
import 'severity.dart';
import 'spacing.dart';

/// An inline banner: a [severity] icon, the severity word, a [message], an
/// optional [action] and an optional dismiss button.
///
/// Controlled: it does not hide itself. When [onDismiss] is set the dismiss
/// button calls it and the caller stops building the banner. (The companion's
/// NotesBanner keeps a dismissed-set per note; that stays there.)
///
/// Accessibility: the severity is shown three ways (icon, visible word,
/// colour) so it never rests on colour; warnings, errors and successes are live
/// regions (announced when they appear); info is not, so a permanent hint does
/// not interrupt anyone. The semantic label is "Warning: message".
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.severity,
    required this.message,
    this.action,
    this.onDismiss,
    this.label,
  });

  final Severity severity;
  final String message;

  /// One optional action ("Release", "Open settings").
  final CandidateAction? action;

  /// When non-null a dismiss button is shown.
  final VoidCallback? onDismiss;

  /// Overrides the severity word, for example "Note" for info.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final style = SeverityStyle.of(context, severity, label: label);
    final theme = Theme.of(context);
    final text = theme.textTheme.bodyMedium?.copyWith(color: style.foreground);
    return Semantics(
      container: true,
      liveRegion: severity != Severity.info,
      label: '${style.label}: $message',
      child: Container(
        color: style.background,
        padding: const EdgeInsets.symmetric(horizontal: kGapM, vertical: kGapS),
        // The label above carries word + message; the icon and text are hidden so
        // they are not read twice. The action and dismiss buttons stay reachable.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: kGapS),
              child: ExcludeSemantics(
                  child: Icon(style.icon, color: style.foreground)),
            ),
            const SizedBox(width: kGapS),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: kGapS),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: '${style.label}: ',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          TextSpan(text: message),
                        ]),
                        style: text,
                      ),
                    ),
                    if (action != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: style.foreground,
                          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: action!.onPressed,
                        child: Text(action!.label),
                      ),
                  ],
                ),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                icon: Icon(Icons.close, color: style.foreground),
                tooltip: 'Dismiss ${style.label}',
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }
}
