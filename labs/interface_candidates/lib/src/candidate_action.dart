import 'package:flutter/foundation.dart';

/// A labelled action: the one button an empty state, a banner, an error view
/// or a toast may carry. Deliberately tiny; it is not a button style.
@immutable
class CandidateAction {
  const CandidateAction({required this.label, required this.onPressed});

  /// Visible label. Also the accessible name, so make it a verb phrase
  /// ("Create a note", "Retry"), not "OK".
  final String label;

  final VoidCallback onPressed;
}
