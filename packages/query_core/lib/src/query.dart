import 'package:async/async.dart';
import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:query_core/src/utils/observer.dart';

part 'paged_query.dart';
part 'paged_query_observer.dart';
part 'paged_query_state.dart';
part 'query_observer.dart';
part 'query_state.dart';

enum QueryStatus {
  idle,
  fetching,
  success,
  failure,
}

extension QueryStatusExtension on QueryStatus {
  bool get isIdle => this == QueryStatus.idle;

  bool get isFetching => this == QueryStatus.fetching;

  bool get isSuccess => this == QueryStatus.success;

  bool get isFailure => this == QueryStatus.failure;
}

typedef QueryId = String;

typedef QueryFetcher<Data> = Future<Data> Function(QueryId id);

abstract class QueryBase {
  QueryBase(this.id);

  final QueryId id;

  Future close();
}

class Query<T> extends QueryBase
    with Observable<QueryObserver<T>, QueryState<T>> {
  Query(QueryId id)
      : _state = QueryState<T>(),
        super(id);

  QueryState<T> _state;

  QueryState<T> get state => _state;

  set state(value) {
    _state = value;
    notify(value);
  }

  CancelableOperation<T>? _cancelableOperation;

  Future fetch({
    required QueryFetcher<T> fetcher,
    Duration staleDuration = Duration.zero,
  }) async {
    if (state.status.isFetching) return;

    if (!isStale(staleDuration) && !state.isInvalidated) return;

    final stateBeforeFetching = state.copyWith();

    state = state.copyWith(
      status: QueryStatus.fetching,
      isInvalidated: false,
    );

    try {
      _cancelableOperation = CancelableOperation<T>.fromFuture(fetcher(id));

      final data = await _cancelableOperation!.valueOrCancellation();

      if (!_cancelableOperation!.isCanceled) {
        state = state.copyWith(
          status: QueryStatus.success,
          data: data,
          dataUpdatedAt: clock.now(),
        );
      } else {
        state = stateBeforeFetching;
      }
    } on Exception catch (error) {
      state = state.copyWith(
        status: QueryStatus.failure,
        error: error,
        errorUpdatedAt: clock.now(),
      );
    }
  }

  Future cancel() async {
    if (!state.status.isFetching) return;

    await _cancelableOperation?.cancel();
  }

  void setInitialData(
    T data, [
    DateTime? updatedAt,
  ]) {
    if (state.hasData) {
      return;
    }

    state = state.copyWith(
      status: QueryStatus.success,
      data: data,
      dataUpdatedAt: updatedAt ?? clock.now(),
    );
  }

  void setData(
    T data, [
    DateTime? updatedAt,
  ]) {
    if (updatedAt != null &&
        state.dataUpdatedAt != null &&
        !updatedAt.isAfter(state.dataUpdatedAt!)) {
      return;
    }

    state = state.copyWith(
      status: QueryStatus.success,
      data: data,
      dataUpdatedAt: updatedAt ?? clock.now(),
    );
  }

  void invalidate() {
    state = state.copyWith(isInvalidated: true);
  }

  bool isStale(Duration duration) {
    if (!state.hasData || state.dataUpdatedAt == null) return true;

    final now = clock.now();
    final staleAt = state.dataUpdatedAt!.add(duration);

    return now.isAfter(staleAt) || now.isAtSameMomentAs(staleAt);
  }

  @override
  Future close() async {
    await _cancelableOperation?.cancel();
  }
}
