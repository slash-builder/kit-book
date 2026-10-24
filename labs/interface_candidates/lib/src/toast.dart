// showToast: one transient message at a time, over ScaffoldMessenger.
//
// Candidate evidence: no demo app has one (nobody wrote it; 4 of 6 apps listed
// it as wanted: minesweeper's win message, notepad's "Could not save",
// render-queue, stopwatch). The larger app has `SnackBar` 50 times in 16 files and a
// `_toast` helper rewritten in 3 places.

import 'package:flutter/material.dart';

import 'candidate_action.dart';
import 'severity.dart';
import 'spacing.dart';

/// Shows [message] as a floating toast (a SnackBar) and returns its controller.
///
/// Single instance: a new toast REPLACES the one on screen at once (no queue,
/// no stacking), so a burst of messages shows only the latest.
///
/// Accessibility: the SnackBar is a live region, so screen readers announce it;
/// the severity is a visible word and an icon as well as a colour; there is
/// always a close button (a timed message must be dismissable). A plain toast
/// times out after 4 s. A toast with an [action] outlives that: 10 s here, and
/// on Flutter 3.29 and later (where SnackBar has `persist`, defaulting to true
/// with an action) it stays until the person acts or closes it, which is what a
/// slow reader or a switch-access user needs.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showToast(
  BuildContext context,
  String message, {
  Severity severity = Severity.info,
  CandidateAction? action,
  Duration? duration,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final style = SeverityStyle.of(context, severity);
  final text =
      Theme.of(context).textTheme.bodyMedium?.copyWith(color: style.foreground);
  // Replace, do not queue: remove whatever is showing without waiting for its
  // exit animation, so the new one appears immediately.
  messenger.removeCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      backgroundColor: style.background,
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
      closeIconColor: style.foreground,
      duration: duration ??
          (action == null
              ? const Duration(seconds: 4)
              : const Duration(seconds: 10)),
      action: action == null
          ? null
          : SnackBarAction(
              label: action.label,
              textColor: style.foreground,
              onPressed: action.onPressed),
      content: Semantics(
        label: '${style.label}: $message',
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(style.icon, color: style.foreground),
            const SizedBox(width: kGapM),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '${style.label}: ',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: message),
                ]),
                style: text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
