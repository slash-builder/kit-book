// ErrorView: the error half of the loading / error / empty / content quartet.
//
// Candidate evidence: the larger app hand-rolls an error state in 15 screens and
// spells the same error banner two ways in 9 calls.

import 'package:flutter/material.dart';

import 'candidate_action.dart';
import 'severity.dart';
import 'spacing.dart';

/// A centred error: icon, the word "Error", a [message] for people, an optional
/// Retry button, and an optional technical [detail] that is collapsed until the
/// person asks for it.
///
/// Accessibility: announced when it appears; the detail toggle's label says
/// what pressing it will do ("Show" / "Hide technical details"); detail text is
/// selectable so it can be copied into a bug report.
class ErrorView extends StatefulWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.detail,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  final String message;

  /// Technical detail (exception text). Collapsed by default.
  final String? detail;

  /// When non-null a Retry button is shown.
  final VoidCallback? onRetry;

  final String retryLabel;

  @override
  State<ErrorView> createState() => _ErrorViewState();
}

class _ErrorViewState extends State<ErrorView> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = SeverityStyle.of(context, Severity.error);
    final scheme = theme.colorScheme;
    final retry = widget.onRetry == null
        ? null
        : CandidateAction(label: widget.retryLabel, onPressed: widget.onRetry!);
    final detail = widget.detail;
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
                      Semantics(
                        container: true,
                        liveRegion: true,
                        label: '${style.label}: ${widget.message}',
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(style.icon,
                                  size: kMinTapTarget, color: scheme.error),
                              const SizedBox(height: kGapM),
                              Text(style.label,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(color: scheme.error)),
                              const SizedBox(height: kGapS),
                              Text(widget.message,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      ),
                      if (retry != null) ...[
                        const SizedBox(height: kGapL),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              minimumSize:
                                  const Size(kMinTapTarget, kMinTapTarget)),
                          onPressed: retry.onPressed,
                          icon: const Icon(Icons.refresh),
                          label: Text(retry.label),
                        ),
                      ],
                      if (detail != null && detail.isNotEmpty) ...[
                        const SizedBox(height: kGapS),
                        // The label carries the state ("Show" / "Hide"), so the
                        // toggle is understandable without seeing the icon.
                        TextButton.icon(
                          style: TextButton.styleFrom(
                              minimumSize:
                                  const Size(kMinTapTarget, kMinTapTarget)),
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          icon: Icon(_expanded
                              ? Icons.expand_less
                              : Icons.expand_more),
                          label: Text(_expanded
                              ? 'Hide technical details'
                              : 'Show technical details'),
                        ),
                        if (_expanded)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              detail,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
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
