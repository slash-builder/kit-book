import 'package:flutter/foundation.dart';

/// What an async view is showing right now. Feed it to [AsyncStateView].
///
/// Sealed, so a `switch` over it is exhaustive. The names avoid `AsyncError`
/// (dart:async) and Riverpod's `AsyncValue` on purpose.
///
/// The larger app already has a `services/view_state.dart` that one screen uses; this
/// is the same idea with the error shape the 15 hand-rolled screens needed
/// (a message plus an optional technical detail).
@immutable
sealed class ViewState<T> {
  const ViewState();

  /// Work in progress; show a spinner.
  const factory ViewState.loading() = ViewLoading<T>;

  /// Loaded, and there is nothing to show.
  const factory ViewState.empty() = ViewEmpty<T>;

  /// Loading failed. [message] is for people; [detail] (an exception string, a
  /// status line) is shown only when they ask for it.
  const factory ViewState.failure(String message, {String? detail}) =
      ViewFailure<T>;

  /// Loaded; show [value].
  const factory ViewState.ready(T value) = ViewReady<T>;

  /// Convenience for list-like results: [ViewEmpty] when [items] is empty,
  /// otherwise [ViewReady].
  static ViewState<List<E>> fromList<E>(List<E> items) =>
      items.isEmpty ? ViewEmpty<List<E>>() : ViewReady<List<E>>(items);
}

final class ViewLoading<T> extends ViewState<T> {
  const ViewLoading();
}

final class ViewEmpty<T> extends ViewState<T> {
  const ViewEmpty();
}

final class ViewFailure<T> extends ViewState<T> {
  const ViewFailure(this.message, {this.detail});

  final String message;
  final String? detail;
}

final class ViewReady<T> extends ViewState<T> {
  const ViewReady(this.value);

  final T value;
}
