import 'package:flutter/material.dart';

/// How serious a message is. Shared by [StatusBanner], [showToast] and
/// [ErrorView] so the four levels look and sound the same everywhere.
enum Severity { info, success, warning, error }

/// What a [Severity] looks like, resolved from the ambient [ColorScheme].
///
/// This is the theming seam for severity: the one place that maps a level to
/// theme roles. When the design system's tone tokens arrive,
/// change this file and nothing else.
///
/// Meaning never rests on colour: every level also has its own icon and its
/// own visible word ([label]).
@immutable
class SeverityStyle {
  const SeverityStyle({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  /// The visible and spoken word ("Warning").
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  static SeverityStyle of(BuildContext context, Severity severity,
      {String? label}) {
    final scheme = Theme.of(context).colorScheme;
    return switch (severity) {
      Severity.info => SeverityStyle(
          label: label ?? 'Info',
          icon: Icons.info_outline,
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        ),
      Severity.success => SeverityStyle(
          label: label ?? 'Success',
          icon: Icons.check_circle_outline,
          background: scheme.primaryContainer,
          foreground: scheme.onPrimaryContainer,
        ),
      Severity.warning => SeverityStyle(
          label: label ?? 'Warning',
          icon: Icons.warning_amber_rounded,
          background: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer,
        ),
      Severity.error => SeverityStyle(
          label: label ?? 'Error',
          icon: Icons.error_outline,
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
        ),
    };
  }
}
