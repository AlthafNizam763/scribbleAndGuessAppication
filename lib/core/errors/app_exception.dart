import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:scribble_guess/core/errors/failure.dart';

/// The one exception type the app throws across a layer boundary.
///
/// Services translate whatever their backend threw into an [AppException]
/// wrapping a [Failure], so repositories, providers and widgets only ever
/// handle a single, closed vocabulary of errors (§57).
class AppException implements Exception {
  const AppException(this.failure, [this.stackTrace]);

  /// Convenience for throwing a bare code.
  AppException.of(AppErrorCode code, [String? message])
      : failure = Failure(code, message ?? Failure.messageFor(code)),
        stackTrace = null;

  /// What went wrong, in the app's own vocabulary.
  final Failure failure;

  /// Where it went wrong, when the original trace was available.
  final StackTrace? stackTrace;

  /// Machine readable category, forwarded from [failure].
  AppErrorCode get code => failure.code;

  /// Copy that is safe to put in front of a player.
  String get userMessage => failure.userMessage;

  /// Whether retrying the same action could reasonably succeed.
  bool get isRetryable => failure.isRetryable;

  @override
  String toString() => 'AppException(${failure.code.name}: ${failure.message})';
}

/// Turns anything thrown by Firebase, `dart:io` or our own code into an
/// [AppException].
///
/// This is the single place that knows Firebase's error vocabulary. Adding a
/// backend means extending this function, not touching call sites.
AppException toAppException(Object error, [StackTrace? stackTrace]) {
  if (error is AppException) return error;

  if (error is FirebaseFunctionsException) {
    return AppException(_fromFunctions(error), stackTrace);
  }
  if (error is FirebaseAuthException) {
    return AppException(
      Failure(AppErrorCode.serverError, error.message ?? error.code),
      stackTrace,
    );
  }
  if (error is FirebaseException) {
    return AppException(_fromFirebase(error), stackTrace);
  }
  if (error is SocketException || error is HttpException) {
    return AppException(const Failure.network(), stackTrace);
  }
  if (error is TimeoutException) {
    return AppException(const Failure.timeout(), stackTrace);
  }
  return AppException(Failure.unknown(error), stackTrace);
}

/// Maps a callable-function error to a [Failure].
///
/// Our functions signal rule violations with `HttpsError('...', message,
/// {code})`, where `code` is an [AppErrorCode] name. That detail is preferred
/// whenever it is present, so the server stays the source of truth for *why*
/// an action was refused; the gRPC status is only the fallback.
Failure _fromFunctions(FirebaseFunctionsException error) {
  final Object? details = error.details;
  if (details is Map) {
    final Object? raw = details['code'];
    if (raw is String) {
      final AppErrorCode code = AppErrorCode.fromName(raw);
      if (code != AppErrorCode.unknown) {
        return Failure(code, error.message ?? Failure.messageFor(code));
      }
    }
  }

  final AppErrorCode code = switch (error.code) {
    'unauthenticated' || 'permission-denied' => AppErrorCode.notHost,
    'not-found' => AppErrorCode.roomNotFound,
    'already-exists' => AppErrorCode.invalidAction,
    'resource-exhausted' => AppErrorCode.roomFull,
    'failed-precondition' => AppErrorCode.invalidAction,
    'invalid-argument' => AppErrorCode.validation,
    'deadline-exceeded' => AppErrorCode.timeout,
    'unavailable' => AppErrorCode.network,
    _ => AppErrorCode.serverError,
  };
  return Failure(code, error.message ?? Failure.messageFor(code));
}

/// Maps a Firestore/Storage/Core error to a [Failure].
Failure _fromFirebase(FirebaseException error) {
  final AppErrorCode code = switch (error.code) {
    'unavailable' || 'network-request-failed' => AppErrorCode.network,
    'deadline-exceeded' => AppErrorCode.timeout,
    'not-found' || 'object-not-found' => AppErrorCode.roomNotFound,
    'permission-denied' || 'unauthorized' => AppErrorCode.invalidAction,
    'unauthenticated' => AppErrorCode.invalidAction,
    _ => AppErrorCode.serverError,
  };
  return Failure(code, error.message ?? error.code);
}
