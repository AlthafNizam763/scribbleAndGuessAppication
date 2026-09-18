import 'package:equatable/equatable.dart';
import 'package:scribble_guess/core/constants/app_strings.dart';

/// Every failure the app can surface, from transport problems to rule
/// violations reported by the server.
enum AppErrorCode {
  /// Nothing more specific is known.
  unknown,

  /// The device could not reach the server at all.
  network,

  /// The server did not answer in time.
  timeout,

  /// The server answered with an internal error.
  serverError,

  /// An established connection dropped.
  connectionLost,

  /// No room exists for the given code.
  roomNotFound,

  /// The room has no free seat.
  roomFull,

  /// The match already started and cannot be joined.
  gameInProgress,

  /// Another player in the room already uses that name.
  nameTaken,

  /// The room code is malformed.
  invalidCode,

  /// The player is banned from the room.
  banned,

  /// The player was removed from the room.
  kicked,

  /// The action requires the host role.
  notHost,

  /// The action requires being the current drawer.
  notDrawer,

  /// The action is not allowed in the current phase.
  invalidAction,

  /// Local input did not pass validation.
  validation,

  /// Reading or writing local storage failed.
  storage,

  /// A voice action was refused because the caller is the current drawer.
  ///
  /// Distinct from [notDrawer], which means the opposite. This is the server
  /// enforcing the one rule voice chat has — the drawer can neither speak nor
  /// hear — and a client that sees it must stop its microphone and close every
  /// peer connection rather than retrying.
  drawerVoiceDisabled;

  /// Whether the server never got as far as deciding anything.
  ///
  /// The distinction is "was the action refused, or did it never happen" — not
  /// "is this error the player's fault". It matters wherever a failed action
  /// leaves something on screen that can be tapped again: a `Room is full` is
  /// a verdict and will be the same verdict next time, while a connection that
  /// never came up has decided nothing and is worth another tap. The
  /// invitation card uses exactly this to choose between dismissing itself and
  /// staying put as its own retry.
  ///
  /// [serverError] is included because `RoomController._diagnose` reports a
  /// reachable-but-broken backend under it, and because a request that died
  /// inside the server is as undecided as one that never arrived.
  bool get isRetryable =>
      this == AppErrorCode.network ||
      this == AppErrorCode.timeout ||
      this == AppErrorCode.connectionLost ||
      this == AppErrorCode.serverError;

  /// Parses a serialized code, falling back to [AppErrorCode.unknown].
  static AppErrorCode fromName(String? value) {
    for (final AppErrorCode code in AppErrorCode.values) {
      if (code.name == value) {
        return code;
      }
    }
    return AppErrorCode.unknown;
  }
}

/// A single, immutable description of something that went wrong.
///
/// [message] carries developer-facing detail, while [userMessage] is the copy
/// that may be shown in the UI.
class Failure extends Equatable {
  /// Creates a failure for [code] with a developer-facing [message].
  const Failure(this.code, this.message, {this.details});

  /// A transport failure: the server could not be reached.
  const Failure.network()
      : this(AppErrorCode.network, AppStrings.errorNetwork);

  /// A request that exceeded its deadline.
  const Failure.timeout() : this(AppErrorCode.timeout, AppStrings.errorTimeout);

  /// A server-side error, optionally carrying the server text.
  const Failure.server([String? message])
      : this(AppErrorCode.serverError, message ?? AppStrings.errorServer);

  /// Invalid local input, where [message] is already user readable.
  const Failure.validation(String message)
      : this(AppErrorCode.validation, message);

  /// An unclassified error, keeping the original [error] in [details].
  const Failure.unknown([Object? error])
      : this(AppErrorCode.unknown, AppStrings.errorUnknown, details: error);

  /// Rebuilds a failure from an `{code, message, details}` payload.
  ///
  /// Malformed payloads never throw: unknown codes and missing text fall back
  /// to sane values.
  factory Failure.fromJson(Map<String, dynamic> json) {
    final Object? rawCode = json['code'];
    final Object? rawMessage = json['message'];
    final AppErrorCode code =
        AppErrorCode.fromName(rawCode is String ? rawCode : null);
    final String message =
        rawMessage is String && rawMessage.trim().isNotEmpty
            ? rawMessage.trim()
            : messageFor(code);
    return Failure(code, message, details: json['details']);
  }

  /// Machine readable category of the failure.
  final AppErrorCode code;

  /// Developer-facing description, often taken straight from the server.
  final String message;

  /// Optional payload such as the original exception or a field name.
  final Object? details;

  /// The copy to show the player for [code].
  static String messageFor(AppErrorCode code) => switch (code) {
        AppErrorCode.unknown => AppStrings.errorUnknown,
        AppErrorCode.network => AppStrings.errorNetwork,
        AppErrorCode.timeout => AppStrings.errorTimeout,
        AppErrorCode.serverError => AppStrings.errorServer,
        AppErrorCode.connectionLost => AppStrings.errorConnectionLost,
        AppErrorCode.roomNotFound => AppStrings.errorRoomNotFound,
        AppErrorCode.roomFull => AppStrings.errorRoomFull,
        AppErrorCode.gameInProgress => AppStrings.errorGameInProgress,
        AppErrorCode.nameTaken => AppStrings.errorNameTaken,
        AppErrorCode.invalidCode => AppStrings.errorInvalidCode,
        AppErrorCode.banned => AppStrings.errorBanned,
        AppErrorCode.kicked => AppStrings.errorKicked,
        AppErrorCode.notHost => AppStrings.errorNotHost,
        AppErrorCode.notDrawer => AppStrings.errorNotDrawer,
        AppErrorCode.invalidAction => AppStrings.errorInvalidAction,
        AppErrorCode.validation => AppStrings.errorValidation,
        AppErrorCode.storage => AppStrings.errorStorage,
        AppErrorCode.drawerVoiceDisabled => AppStrings.voiceDrawerDisabled,
      };

  /// Copy safe to show in the UI.
  ///
  /// Validation failures carry their own already-friendly [message]; every
  /// other code maps to a curated `AppStrings` entry.
  String get userMessage =>
      code == AppErrorCode.validation && message.trim().isNotEmpty
          ? message
          : messageFor(code);

  /// Whether retrying the same action could reasonably succeed.
  bool get isRetryable =>
      code == AppErrorCode.network ||
      code == AppErrorCode.timeout ||
      code == AppErrorCode.connectionLost ||
      code == AppErrorCode.serverError;

  /// Serializes this failure to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'code': code.name,
        'message': message,
        if (details != null) 'details': _jsonSafeDetails(details),
      };

  /// Returns a copy with the given fields replaced.
  Failure copyWith({AppErrorCode? code, String? message, Object? details}) =>
      Failure(
        code ?? this.code,
        message ?? this.message,
        details: details ?? this.details,
      );

  static Object? _jsonSafeDetails(Object? value) => switch (value) {
        null => null,
        String() || num() || bool() => value,
        Map<String, dynamic>() => value,
        List<Object?>() => value,
        _ => value.toString(),
      };

  @override
  List<Object?> get props => <Object?>[code, message, details];

  @override
  bool get stringify => true;
}
