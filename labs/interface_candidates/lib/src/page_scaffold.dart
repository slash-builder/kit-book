// PageScaffold: the one page convention (app bar, banner slot, body, footer).
//
// Candidate evidence: 6 of 6 demo apps build `Scaffold` + `AppBar(title:
// manifest.name, actions: [...])` by hand (launcher and render-queue mark it
// "Interface Kit: page scaffold"; stopwatch adds a footer status line; notepad
// is master/detail with a status bar). The larger app has two competing conventions:
// its own app-bar widget in 27 files and a raw `AppBar` in 21 others.

import 'package:flutter/material.dart';

import 'spacing.dart';

// The banner slot and the footer slot are capped to a share of the page height
// and scroll inside that share, so at large text scales (or a very long
// notice) they can never push the body off the screen.
const double _kBannerMaxShare = 0.4;
const double _kFooterMaxShare = 0.25;

/// A page: an app bar with [title], optional [subtitle] and [actions]; a
/// [banner] slot above the body; the body; a [footer] slot (status line) below.
///
/// Use the default constructor for a single-pane page and
/// [PageScaffold.masterDetail] for list + detail (notepad's shape): at widths
/// of [wideBreakpoint] and up both panes are shown side by side; below it only
/// one is shown at a time, chosen by [showDetail].
///
/// Accessibility: the title is a heading; in the narrow master/detail layout a
/// labelled 48 dp Back button replaces the detail; each pane is its own focus
/// group, so Tab walks the whole master pane and then the whole detail pane;
/// the app bar grows with the text scale when a subtitle is present, and long
/// titles end in an ellipsis rather than overflowing (the full title is still
/// what a screen reader says).
class PageScaffold extends StatelessWidget {
  /// A single-pane page.
  const PageScaffold({
    super.key,
    required this.title,
    required Widget this.body,
    this.subtitle,
    this.actions = const [],
    this.banner,
    this.footer,
  })  : master = null,
        detail = null,
        showDetail = false,
        onDetailBack = null,
        masterWidth = kMasterPaneWidth,
        wideBreakpoint = kWideBreakpoint,
        masterLabel = null,
        detailLabel = null;

  /// A list + detail page.
  const PageScaffold.masterDetail({
    super.key,
    required this.title,
    required Widget this.master,
    required Widget this.detail,
    this.subtitle,
    this.actions = const [],
    this.banner,
    this.footer,
    this.showDetail = false,
    this.onDetailBack,
    this.masterWidth = kMasterPaneWidth,
    this.wideBreakpoint = kWideBreakpoint,
    this.masterLabel,
    this.detailLabel,
  }) : body = null;

  final String title;
  final String? subtitle;

  /// App bar actions, for example a mode badge and icon buttons. Give icon
  /// buttons a `tooltip`: it is their accessible name.
  final List<Widget> actions;

  /// Shown full width above the body, for example a [StatusBanner]. Capped to
  /// 40% of the page height (scrolls inside that).
  final Widget? banner;

  /// Shown full width below the body, for example a [SaveStatusChip]. Capped to
  /// 25% of the page height.
  final Widget? footer;

  final Widget? body;
  final Widget? master;
  final Widget? detail;

  /// Narrow layout only: show the detail pane instead of the master pane.
  final bool showDetail;

  /// Narrow layout only, with [showDetail]: called by the Back button. Without
  /// it there is no Back button and the caller must provide its own way back.
  final VoidCallback? onDetailBack;

  final double masterWidth;
  final double wideBreakpoint;

  /// Optional accessible names for the two panes ("Notes", "Editor").
  final String? masterLabel;
  final String? detailLabel;

  bool get _isMasterDetail => master != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, page) {
        final wide = _isMasterDetail && page.maxWidth >= wideBreakpoint;
        final backToList =
            _isMasterDetail && !wide && showDetail && onDetailBack != null;
        return Scaffold(
          appBar: AppBar(
            centerTitle: false,
            toolbarHeight: _toolbarHeight(context),
            leading: backToList
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: onDetailBack)
                : null,
            title: _Title(title: title, subtitle: subtitle),
            actions: [...actions, const SizedBox(width: kGapS)],
          ),
          body: LayoutBuilder(
            builder: (context, area) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (banner != null)
                    _Capped(
                        maxHeight: area.maxHeight * _kBannerMaxShare,
                        child: banner!),
                  Expanded(child: _content(wide)),
                  if (footer != null)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        border: Border(
                            top: BorderSide(color: scheme.outlineVariant)),
                      ),
                      child: SafeArea(
                        top: false,
                        child: _Capped(
                            maxHeight: area.maxHeight * _kFooterMaxShare,
                            child: footer!),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _content(bool wide) {
    if (!_isMasterDetail) return body!;
    Widget pane(Widget child, String? label) => FocusTraversalGroup(
          child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: label,
              child: child),
        );
    if (!wide) {
      return showDetail
          ? pane(detail!, detailLabel)
          : pane(master!, masterLabel);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: masterWidth, child: pane(master!, masterLabel)),
        const VerticalDivider(width: 1),
        Expanded(child: pane(detail!, detailLabel)),
      ],
    );
  }

  /// With a subtitle the title block is two lines; measure them at the current
  /// text scale so the app bar is tall enough at 2.0 and does not overflow.
  double? _toolbarHeight(BuildContext context) {
    if (subtitle == null) return null;
    final theme = Theme.of(context);
    // AppBar itself clamps its title's text scale to 1.34 (its private
    // _kMaxTitleTextScaleFactor); measure with the same clamp.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.34);
    double lineHeight(TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: style),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
      )..layout();
      final h = painter.height;
      painter.dispose();
      return h;
    }

    final needed = lineHeight(theme.textTheme.titleLarge) +
        lineHeight(theme.textTheme.bodySmall) +
        kGapS;
    return needed > kToolbarHeight ? needed : null;
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.title, required this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Semantics(
      header: true,
      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    if (subtitle == null) return heading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading,
        Text(
          subtitle!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Capped extends StatelessWidget {
  const _Capped({required this.maxHeight, required this.child});

  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(child: child),
      );
}
