import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:scribble_guess/core/errors/app_exception.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// The single place the app calls a Cloud Function.
///
/// Wrapping `httpsCallable` here buys three things every call site would
/// otherwise have to repeat: a deadline, translation of Firebase's error
/// vocabulary into [AppException], and a guarantee that the result is a
/// string-keyed map rather than whatever `dynamic` came back.
class FunctionsClient {
  FunctionsClient({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// How long to wait before giving up on a callable.
  ///
  /// Generous enough for a cold start on a free-tier project, short enough
  /// that a player is not left staring at a spinner forever (§57).
  static const Duration _timeout = Duration(seconds: 20);

  /// Invokes [name] with [data] and returns the response map.
  ///
  /// Throws [AppException] for every failure, including timeouts, so callers
  /// only ever catch one type.
  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      final HttpsCallableResult<dynamic> result = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: _timeout),
          )
          .call<dynamic>(data ?? <String, dynamic>{});

      return asMap(result.data);
    } on FirebaseFunctionsException catch (error, stack) {
      // Logged at warning, not error: a refused action (room full, not the
      // host) is a normal outcome, not a defect.
      AppLogger.w('callable "$name" refused: ${error.code}', error);
      throw toAppException(error, stack);
    } on TimeoutException catch (error, stack) {
      AppLogger.w('callable "$name" timed out', error);
      throw toAppException(error, stack);
    } on Object catch (error, stack) {
      AppLogger.e('callable "$name" failed', error, stack);
      throw toAppException(error, stack);
    }
  }
}
