// StatusDotRow: a list row led by a status dot.
//
// Candidate evidence is THIN here (see README): launcher's roster row has a dot
// plus a status word (running / stale / gone / not running); render-queue's job
// tile has a state chip, not a dot; notepad's note row has the overflow menu but
// no dot. The larger app's services row was named in the original request but not read for this
// package. The shared shape is "ListTile + status + optional overflow menu".

import 'package:flutter/material.dart';

import 'candidate_action.dart';
import 'spacing.dart';

/// How a row's status reads at a glance. Deliberately generic; the app maps its
/// own states (running, stale, gone, queued...) onto these four and supplies the
/// words.
enum StatusTone { ok, attention, problem, idle }

/// A list row: status dot, [title], a second line made of the visible
/// [statusLabel] and an optional [subtitle], an optional [trailing] widget and
/// an optional overflow [menu].
///
/// The dot is never the only carrier of the status: [statusLabel] is required
/// and shown as text, and each tone has its own dot SHAPE (filled circle,
/// triangle, square, hollow circle) as well as its own colour.
///
/// Accessibility: the dot is hidden from screen readers (the label says it);
/// the row reads as "title, status label · subtitle"; the overflow button is
/// 48 dp and named "More actions for <title>".
class StatusDotRow extends StatelessWidget {
  const StatusDotRow({
    super.key,
    required this.tone,
    required this.statusLabel,
    required this.title,
    this.subtitle,
    this.trailing,
    this.menu = const [],
    this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  final StatusTone tone;

  /// Visible and spoken status ("Running", "Stale", "Not saved").
  final String statusLabel;

  final String title;
  final String? subtitle;

  /// Shown before the overflow menu, for example an uptime or a chip.
  final Widget? trailing;

  /// Overflow menu entries ("Rename", "Delete"). Empty means no menu button.
  final List<CandidateAction> menu;

  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;

  static IconData _shape(StatusTone tone) => switch (tone) {
        StatusTone.ok => Icons.circle,
        StatusTone.attention => Icons.change_history,
        StatusTone.problem => Icons.square,
        StatusTone.idle => Icons.circle_outlined,
      };

  static Color _color(ColorScheme scheme, StatusTone tone) => switch (tone) {
        StatusTone.ok => scheme.primary,
        StatusTone.attention => scheme.tertiary,
        StatusTone.problem => scheme.error,
        StatusTone.idle => scheme.outline,
      };

  @override
  Widget build(BuildContext context) {
    final second = [
      statusLabel,
      if (subtitle != null && subtitle!.isNotEmpty) subtitle!
    ].join(' · ');
    final hasTrailing = trailing != null || menu.isNotEmpty;
    // ListTile asserts when its trailing widget takes the whole row, so the
    // trailing slot is capped at half the row and wraps inside that.
    return LayoutBuilder(
      builder: (context, constraints) =>
          _tile(context, constraints.maxWidth / 2, hasTrailing, second),
    );
  }

  Widget _tile(BuildContext context, double trailingMaxWidth, bool hasTrailing,
      String second) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      enabled: enabled,
      selected: selected,
      onTap: onTap,
      leading: ExcludeSemantics(
        child: Icon(_shape(tone),
            size: kDotSize,
            color: enabled
                ? _color(scheme, tone)
                : Theme.of(context).disabledColor),
      ),
      horizontalTitleGap: kGapM,
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(second, maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: hasTrailing
          ? ConstrainedBox(
              constraints: BoxConstraints(maxWidth: trailingMaxWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trailing != null) Flexible(child: trailing!),
                  if (menu.isNotEmpty)
                    PopupMenuButton<int>(
                      enabled: enabled,
                      tooltip: 'More actions for $title',
                      onSelected: (i) => menu[i].onPressed(),
                      itemBuilder: (context) => [
                        for (var i = 0; i < menu.length; i++)
                          PopupMenuItem<int>(
                              value: i, child: Text(menu[i].label)),
                      ],
                    ),
                ],
              ),
            )
          : null,
    );
  }
}
