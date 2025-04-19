abstract class Result<T> {
  bool get isSuccess;
  bool get isFailure;

  T? get valueOrNull;
  Object? get errorOrNull;

  factory Result.success(T value) = _Success<T>;
  factory Result.failure(Object error) = _Failure<T>;

  // 必须实现的方法
  S fold<S>({
    required S Function(T value) onSuccess,
    required S Function(Object error) onFailure,
  });

  Result<R> map<R>(R Function(T value) transform);

  Result<R> flatMap<R>(Result<R> Function(T value) transform);

  void onSuccess(void Function(T value) action);

  void onFailure(void Function(Object error) action);
}

class _Success<T> implements Result<T> {
  final T value;
  _Success(this.value);

  @override
  bool get isSuccess => true;
  @override
  bool get isFailure => false;

  @override
  T? get valueOrNull => value;
  @override
  Object? get errorOrNull => null;

  @override
  S fold<S>({
    required S Function(T value) onSuccess,
    required S Function(Object error) onFailure,
  }) =>
      onSuccess(value);

  @override
  Result<R> map<R>(R Function(T value) transform) {
    return Result.success(transform(value));
  }

  @override
  Result<R> flatMap<R>(Result<R> Function(T value) transform) {
    return transform(value);
  }

  @override
  void onSuccess(void Function(T value) action) => action(value);

  @override
  void onFailure(void Function(Object error) action) {}
}

class _Failure<T> implements Result<T> {
  final Object error;
  _Failure(this.error);

  @override
  bool get isSuccess => false;
  @override
  bool get isFailure => true;

  @override
  T? get valueOrNull => null;
  @override
  Object? get errorOrNull => error;

  @override
  S fold<S>({
    required S Function(T value) onSuccess,
    required S Function(Object error) onFailure,
  }) =>
      onFailure(error);

  @override
  Result<R> map<R>(R Function(T value) transform) {
    return Result.failure(error);
  }

  @override
  Result<R> flatMap<R>(Result<R> Function(T value) transform) {
    return Result.failure(error);
  }

  @override
  void onSuccess(void Function(T value) action) {}

  @override
  void onFailure(void Function(Object error) action) => action(error);
}
