import 'package:equatable/equatable.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// Device-local preferences, persisted with the storage service.
class AppSettings extends Equatable {
  /// Creates app settings.
  const AppSettings({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.reducedMotion = false,
    this.themeMode = SketchThemeMode.system,
    this.language = AppLanguage.en,
    this.serverUrl = AppConstants.defaultServerUrl,
  });

  /// Builds settings from a decoded JSON map, tolerating malformed values.
  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        soundEnabled: asBool(json['soundEnabled'], defaults.soundEnabled),
        hapticsEnabled: asBool(json['hapticsEnabled'], defaults.hapticsEnabled),
        reducedMotion: asBool(json['reducedMotion'], defaults.reducedMotion),
        themeMode: SketchThemeMode.fromName(asString(json['themeMode'])),
        language: AppLanguage.fromName(asString(json['language'])),
        serverUrl: asString(json['serverUrl'], defaults.serverUrl),
      );

  /// The settings a fresh install starts with.
  static const AppSettings defaults = AppSettings();

  /// Whether sound effects play.
  final bool soundEnabled;

  /// Whether haptic feedback fires.
  final bool hapticsEnabled;

  /// Whether animations are short-circuited for accessibility.
  final bool reducedMotion;

  /// Which palette the app renders with.
  final SketchThemeMode themeMode;

  /// The language the interface is presented in.
  ///
  /// Device-local and deliberately separate from a room's word language: a
  /// player whose phone is in Tamil can still join an English word bank, and
  /// changing the interface language must not silently change what everybody
  /// in the room is drawing. The room setting travels to the server; this one
  /// never leaves the device.
  final AppLanguage language;

  /// The player's own backend address, or empty to follow the build.
  ///
  /// Empty is the normal state and means "use `AppConfig.apiBaseUrl`", which
  /// is the deployed backend. A non-empty value overrides it, which is how two
  /// physical phones are pointed at one laptop for local testing.
  final String serverUrl;

  /// Serializes these settings to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'soundEnabled': soundEnabled,
        'hapticsEnabled': hapticsEnabled,
        'reducedMotion': reducedMotion,
        'themeMode': themeMode.name,
        'language': language.name,
        'serverUrl': serverUrl,
      };

  /// Returns a copy with the given fields replaced.
  AppSettings copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? reducedMotion,
    SketchThemeMode? themeMode,
    AppLanguage? language,
    String? serverUrl,
  }) =>
      AppSettings(
        soundEnabled: soundEnabled ?? this.soundEnabled,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        reducedMotion: reducedMotion ?? this.reducedMotion,
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
        serverUrl: serverUrl ?? this.serverUrl,
      );

  @override
  List<Object?> get props => <Object?>[
        soundEnabled,
        hapticsEnabled,
        reducedMotion,
        themeMode,
        language,
        serverUrl,
      ];

  @override
  bool get stringify => true;
}
