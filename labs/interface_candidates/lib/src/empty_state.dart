// EmptyState: "nothing here yet", with at most one way forward.
//
// Candidate evidence: hand-built in notepad (ValueKey('empty-state')), launcher
// and render-queue (each marked "Interface Kit: empty state" in its source), and
// The larger app has 5 near-identical `_empty()` methods (catching-up, files, house,
// messages, media).

import 'package:flutter/material.dart';

import 'candidate_action.dart';
import 'spacing.dart';

/// A centred message for a view that has nothing to show: an icon (or any
/// custom [leading] widget), a [title], an optional [body], and at most one
/// primary [action].
///
/// Accessibility: the title is a heading, the icon is decorative (hidden from
/// screen readers), and the block scrolls instead of overflowing at large text
/// scales.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.body,
    this.action,
  }) : assert(icon == null || leading == null,
            'Give an icon or a leading widget, not both.');

  /// Headline, for example "No notes yet".
  final String title;

  /// A Material icon shown above the title. Decorative.
  final IconData? icon;

  /// A custom leading widget (an illustration). Replaces [icon]. Treated as
  /// decorative; give it its own Semantics if it carries meaning.
  final Widget? leading;

  /// One or two sentences saying why it is empty or what to do.
  final String? body;

  /// The single primary action, for example "Create a note".
  final CandidateAction? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lead = leading ??
        (icon == null
            ? null
            : Icon(icon, size: kMinTapTarget, color: scheme.onSurfaceVariant));
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight:
                    constraints.hasBoundedHeight ? constraints.maxHeight : 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kStateMaxWidth),
                child: Padding(
                  padding: const EdgeInsets.all(kGapXl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (lead != null) ...[
                        ExcludeSemantics(child: lead),
                        const SizedBox(height: kGapL)
                      ],
                      Semantics(
                        header: true,
                        child: Text(title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium),
                      ),
                      if (body != null) ...[
                        const SizedBox(height: kGapS),
                        Text(
                          body!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                      if (action != null) ...[
                        const SizedBox(height: kGapL),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              minimumSize:
                                  const Size(kMinTapTarget, kMinTapTarget)),
                          onPressed: action!.onPressed,
                          child:
                              Text(action!.label, textAlign: TextAlign.center),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
