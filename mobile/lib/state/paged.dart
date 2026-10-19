import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../models/common.dart';

class PagedState<T> {
  const PagedState({
    this.items = const [],
    this.page = 0,
    this.hasMore = true,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.total = 0,
    this.loadMoreError,
  });
  final List<T> items;
  final int page, total;
  final bool hasMore, loading, loadingMore;
  final Object? error, loadMoreError;

  bool get isEmpty => items.isEmpty && !loading && error == null;
  PagedState<T> copyWith({
    List<T>? items,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    Object? error,
    Object? loadMoreError,
    int? total,
    bool clearError = false,
    bool clearMoreError = false,
  }) => PagedState(
    items: items ?? this.items,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
    loadMoreError: clearMoreError ? null : (loadMoreError ?? this.loadMoreError),
    total: total ?? this.total,
  );
}

/// Base for server-paginated lists: first page loads on build, [loadMore] appends, [refresh] resets.
abstract class PagedNotifier<T> extends Notifier<PagedState<T>> {
  Future<Paged<T>> fetch(int page);

  /// Called synchronously from build(): `ref.watch` providers here so the list resets when they change.
  void deps() {}

  bool _disposed = false;

  @override
  PagedState<T> build() {
    _disposed = false;
    deps();
    ref.onDispose(() => _disposed = true);
    Future.microtask(() => _load(1, reset: true));
    return const PagedState(loading: true);
  }

  Future<void> refresh() => _load(1, reset: true);

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    await _load(state.page + 1);
  }

  /// Automatic (scroll-triggered) callers must not fire while loadMoreError is set; the footer Retry button
  /// calls this directly and so clears the error and tries again.
  /// Local mutation helper (e.g. remove an unfavourited row).
  void mutate(List<T> Function(List<T>) f) => state = state.copyWith(items: f(state.items));

  Future<void> _load(int page, {bool reset = false}) async {
    if (_disposed) return;
    state = reset
        ? state.copyWith(loading: true, clearError: true, clearMoreError: true)
        : state.copyWith(loadingMore: true, clearMoreError: true);
    try {
      final r = await fetch(page);
      if (_disposed) return;
      state = PagedState(
        items: reset ? r.items : [...state.items, ...r.items],
        page: r.meta.page,
        hasMore: r.meta.hasMore && r.items.isNotEmpty,
        total: r.meta.total,
      );
    } catch (e) {
      if (_disposed) return;
      final err = e is AppException ? e : AppException(ErrorKind.unknown, '$e');
      state = reset
          ? state.copyWith(loading: false, error: err)
          : state.copyWith(loadingMore: false, loadMoreError: err);
    }
  }
}
