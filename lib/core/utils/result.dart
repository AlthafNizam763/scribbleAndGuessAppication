import 'dart:async';

import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';

/// The outcome of an operation that can fail: either an [Ok] value or an
/// [Err] carrying a [Failure].
///
/// Nothing in the app throws across a repository boundary; it returns a
/// `Result` instead.
sealed class Result<T> {
  /// Const base constructor for the two variants.
  const Result();
}

/// A successful [Result] holding [value].
final class Ok<T> extends Result<T> {
  /// Wraps a successful [value].
  const Ok(this.value);

  /// The produced value.
  final T value;

  @override
  String toString() => 'Ok($value)';
}

/// A failed [Result] holding [failure].
final class Err<T> extends Result<T> {
  /// Wraps the [failure] that stopped the operation.
  const Err(this.failure);

  /// What went wrong.
  final Failure failure;

  @override
  String toString() => 'Err(${failure.code.name}: ${failure.message})';
}

/// Ergonomic accessors shared by both [Result] variants.
extension ResultX<T> on Result<T> {
  /// Whether this result succeeded.
  bool get isOk => this is Ok<T>;

  /// Whether this result failed.
  bool get isErr => this is Err<T>;

  /// The value on success, or `null` on failure.
  T? get valueOrNull => switch (this) {
        Ok<T>(:final T value) => value,
        Err<T>() => null,
      };

  /// The failure on error, or `null` on success.
  Failure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final Failure failure) => failure,
      };

  /// The value on success, or [fallback] on failure.
  T valueOr(T fallback) => switch (this) {
        Ok<T>(:final T value) => value,
        Err<T>() => fallback,
      };

  /// Collapses both variants into a single value.
  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) =>
      switch (this) {
        Ok<T>(:final T value) => onOk(value),
        Err<T>(:final Failure failure) => onErr(failure),
      };

  /// Transforms a successful value, passing failures through untouched.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T>(:final T value) => Ok<R>(transform(value)),
        Err<T>(:final Failure failure) => Err<R>(failure),
      };

  /// Chains another fallible step onto a successful value.
  Result<R> flatMap<R>(Result<R> Function(T value) transform) => switch (this) {
        Ok<T>(:final T value) => transform(value),
        Err<T>(:final Failure failure) => Err<R>(failure),
      };

  /// Runs [onOk] only when this result succeeded.
  void whenOk(void Function(T value) onOk) {
    if (this case Ok<T>(:final T value)) {
      onOk(value);
    }
  }

  /// Runs [onErr] only when this result failed.
  void whenErr(void Function(Failure failure) onErr) {
    if (this case Err<T>(:final Failure failure)) {
      onErr(failure);
    }
  }
}

/// Runs [body] and converts any thrown object into an [Err].
///
/// Timeouts become [AppErrorCode.timeout], transport errors become
/// [AppErrorCode.network] and everything else becomes [AppErrorCode.unknown].
/// `dart:io` is deliberately not imported so this works on the web too.
Future<Result<T>> guard<T>(Future<T> Function() body) async {
  try {
    return Ok<T>(await body());
  } on TimeoutException catch (error) {
    AppLogger.w('guard: timed out', error);
    return Err<T>(
      Failure(AppErrorCode.timeout, AppStrings.errorTimeout, details: error),
    );
  } catch (error, stackTrace) {
    AppLogger.e('guard: ${error.runtimeType}', error, stackTrace);
    return Err<T>(failureFrom(error));
  }
}

/// Classifies an arbitrary thrown [error] into a [Failure].
///
/// Transport exceptions are recognised by name rather than by type so the
/// classification also works in a browser, where `dart:io` does not exist.
Failure failureFrom(Object error) {
  if (error is Failure) {
    return error;
  }
  if (error is TimeoutException) {
    return Failure(
      AppErrorCode.timeout,
      AppStrings.errorTimeout,
      details: error,
    );
  }
  final String signature = '${error.runtimeType} $error'.toLowerCase();
  const List<String> networkMarkers = <String>[
    'socketexception',
    'httpexception',
    'handshakeexception',
    'clientexception',
    'websocketexception',
    'connection refused',
    'connection closed',
    'connection reset',
    'failed host lookup',
    'network is unreachable',
    'xmlhttprequest error',
  ];
  for (final String marker in networkMarkers) {
    if (signature.contains(marker)) {
      return Failure(
        AppErrorCode.network,
        AppStrings.errorNetwork,
        details: error,
      );
    }
  }
  return Failure.unknown(error);
}
