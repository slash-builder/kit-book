// AsyncStateView: one widget for loading / empty / error / content.
//
// Replaces the 15 screens of the larger app that handle the four states by hand (and the
// 7 pasted `Center(CircularProgressIndicator())`). In the six demo apps it
// would replace launcher's `snap == null ? loading : rows.isEmpty ? empty :
// list` ladder, render-queue's and notepad's `isEmpty ? empty : list`.

import 'package:flutter/material.dart';

import 'empty_state.dart';
import 'error_view.dart';
import 'loading_view.dart';
import 'view_state.dart';

/// Renders a [ViewState]: [LoadingView], an [EmptyState], an [ErrorView] with
/// Retry, or [builder]'s content.
///
/// ```dart
/// AsyncStateView<List<Job>>(
///   state: state,
///   empty: const EmptyState(icon: Icons.work_outline, title: 'No jobs'),
///   onRetry: reload,
///   builder: (context, jobs) => JobList(jobs),
/// )
/// ```
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.state,
    required this.builder,
    this.empty,
    this.loadingLabel = 'Loading',
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  final ViewState<T> state;

  /// Builds the content for [ViewReady].
  final Widget Function(BuildContext context, T value) builder;

  /// Shown for [ViewEmpty]. Defaults to a plain "Nothing here yet".
  final Widget? empty;

  final String loadingLabel;

  /// Retry callback for [ViewFailure]. With null, no Retry button is shown
  /// (some failures cannot be retried).
  final VoidCallback? onRetry;

  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      ViewLoading<T>() => LoadingView(label: loadingLabel),
      ViewEmpty<T>() => empty ?? const EmptyState(title: 'Nothing here yet'),
      ViewFailure<T>(:final message, :final detail) => ErrorView(
          message: message,
          detail: detail,
          onRetry: onRetry,
          retryLabel: retryLabel),
      ViewReady<T>(:final value) => builder(context, value),
    };
  }
}
