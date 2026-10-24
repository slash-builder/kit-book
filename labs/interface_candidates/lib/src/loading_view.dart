// LoadingView: the centred spinner.
//
// Candidate evidence: launcher ("Interface Kit: loading view"); the larger app pastes
// `Center(CircularProgressIndicator())` 7 times.

import 'package:flutter/material.dart';

import 'spacing.dart';

/// A centred progress indicator with a visible [label] and a matching
/// accessible name, announced when it appears.
///
/// The spinner animates forever, so in widget tests use `pump()`, never
/// `pumpAndSettle()`.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading'});

  /// Shown under the spinner and spoken by screen readers.
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Semantics(
        container: true,
        liveRegion: true,
        label: label,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.all(kGapXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: kGapL),
                Text(label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
