import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';

/// Physical feedback paired with a sound.
///
/// Sound and vibration are two renderings of the same event, so they are
/// declared together on [SoundEffect] rather than being wired up separately at
/// every call site. A screen says "a correct guess happened"; how loudly and
/// how firmly that lands is decided here, once.
enum Haptic {
  /// Nothing. For cues that fire often enough that buzzing would be noise.
  none,

  /// The lightest tap the platform offers, for discrete UI changes.
  selection,

  /// A light impact, for a small confirmation.
  light,

  /// A medium impact, for something the player is meant to notice.
  medium,

  /// A heavy impact, reserved for the end of a turn or a game.
  heavy,
}

/// Every sound the game can play.
///
/// [asset] names a file under `assets/sounds/`, all of which are synthesized by
/// `tool/generate_sound_assets.dart` — add a case here and a score there, in
/// that order, and re-run the tool.
enum SoundEffect {
  /// A button was pressed.
  tap('tap', Haptic.selection),

  /// Somebody else guessed the word.
  correctGuess('correct_guess', Haptic.none),

  /// You guessed the word.
  correctSelf('correct_self', Haptic.medium),

  /// A guess was one letter away.
  closeGuess('close_guess', Haptic.light),

  /// A letter of the word was revealed.
  hint('hint', Haptic.none),

  /// A player joined the room.
  playerJoined('player_joined', Haptic.none),

  /// A player left the room.
  playerLeft('player_left', Haptic.none),

  /// You are the drawer and must pick a word.
  yourTurn('your_turn', Haptic.medium),

  /// The drawing phase began.
  turnStart('turn_start', Haptic.light),

  /// The turn ended and the round result is up.
  roundEnd('round_end', Haptic.light),

  /// The game ended and final standings are up.
  gameEnd('game_end', Haptic.heavy),

  /// One second passed near the end of a turn.
  tick('tick', Haptic.none),

  /// The clock ran out with the word unguessed.
  timeUp('time_up', Haptic.heavy);

  const SoundEffect(this._file, this.haptic);

  final String _file;

  /// The vibration that accompanies this sound.
  final Haptic haptic;

  /// Path of the backing file, relative to the `assets/` root.
  ///
  /// `AssetSource` prepends `assets/` itself, which is why this does not.
  String get asset => 'sounds/$_file.wav';
}

/// Plays the game's sound effects and fires its haptics.
///
/// ## Why a fixed pool of players rather than one per sound
///
/// Several effects can legitimately overlap — a hint lands while somebody is
/// guessing, two players guess within the same second — and a single
/// [AudioPlayer] handed a new source cuts off whatever it was playing. So this
/// keeps a small ring of players and rotates through them, which means the
/// last [_poolSize] sounds can all be ringing at once.
///
/// The ring is fixed-size rather than one player per [SoundEffect] because each
/// player is a real platform object (an Android `MediaPlayer`, an iOS
/// `AVAudioPlayer`). Four covers every overlap this game actually produces;
/// thirteen would be thirteen live decoders idling through a whole match to
/// buy nothing.
///
/// ## Failure is not an error
///
/// Every path here swallows its exceptions. An emulator with no audio device, a
/// phone whose session was taken by an incoming call, a codec that refuses the
/// file: none of that is a reason for a guess not to register. Audio is
/// decoration, and decoration must never be able to fail a turn.
class SoundService {
  /// Creates a service. Nothing touches the platform until [warmUp].
  SoundService();

  /// How many sounds may ring simultaneously.
  static const int _poolSize = 4;

  /// Master volume. Below 1.0 because these are synthesized at a fixed peak and
  /// sit on top of whatever the player is already listening to.
  static const double _volume = 0.7;

  final List<AudioPlayer> _pool = <AudioPlayer>[];
  int _next = 0;

  /// Whether sounds play. Mirrors `AppSettings.soundEnabled`.
  bool soundEnabled = true;

  /// Whether vibration fires. Mirrors `AppSettings.hapticsEnabled`.
  bool hapticsEnabled = true;

  bool _ready = false;
  bool _broken = false;
  Future<void>? _warmUp;

  /// Prepares the players and unpacks the assets.
  ///
  /// Safe to call repeatedly; the work happens once. [play] calls it so a
  /// caller never has to, but calling it early — when a room is joined — is
  /// what stops the *first* sound of a session from arriving late, which is the
  /// one place the delay would be noticeable.
  Future<void> warmUp() => _warmUp ??= _prepare();

  Future<void> _prepare() async {
    try {
      // Sonification, not media, and no audio focus: these are blips over the
      // top of whatever else the phone is doing. Somebody listening to music
      // while they draw should keep hearing it, and a guess should not pause
      // their podcast. On iOS the `ambient` category means the same thing, and
      // additionally respects the hardware mute switch — which is the right
      // behaviour for a game whose audio is decoration.
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        ),
      );

      for (int i = 0; i < _poolSize; i++) {
        final AudioPlayer player = AudioPlayer();
        unawaited(player.setReleaseMode(ReleaseMode.stop));
        _pool.add(player);
      }

      // Extracts every asset to a cache file up front. Without this the first
      // play of each effect pays for a bundle read on the platform thread.
      await AudioCache.instance.loadAll(
        <String>[
          for (final SoundEffect effect in SoundEffect.values) effect.asset,
        ],
      );

      _ready = true;
    } on Object catch (error, stack) {
      // No audio device, no codec, no permission — all the same outcome, and
      // all of them mean "play nothing" rather than "crash".
      _broken = true;
      AppLogger.w('Sound unavailable; continuing muted', error, stack);
    }
  }

  /// Plays [effect] and fires its haptic, honouring both settings.
  ///
  /// Returns immediately: the play is dispatched and never awaited, because a
  /// caller reacting to a game event must not be made to wait on a speaker.
  void play(SoundEffect effect) {
    if (hapticsEnabled) {
      _vibrate(effect.haptic);
    }
    if (!soundEnabled || _broken) {
      return;
    }
    unawaited(_playAsset(effect));
  }

  Future<void> _playAsset(SoundEffect effect) async {
    try {
      await warmUp();
      if (!_ready || _pool.isEmpty) {
        return;
      }
      // Re-checked after the await: the toggle may have moved while the assets
      // were unpacking, and the first play of a session is exactly when that is
      // most likely, because the player just came from the settings screen.
      if (!soundEnabled) {
        return;
      }

      final AudioPlayer player = _pool[_next];
      _next = (_next + 1) % _pool.length;

      await player.stop();
      await player.play(AssetSource(effect.asset), volume: _volume);
    } on Object catch (error) {
      // Debug level: one failed blip is not worth a warning in a release log,
      // and the interesting failure — the whole subsystem being unavailable —
      // is already reported by [_prepare].
      AppLogger.d('Could not play ${effect.name}', error);
    }
  }

  void _vibrate(Haptic haptic) {
    try {
      switch (haptic) {
        case Haptic.none:
          return;
        case Haptic.selection:
          unawaited(HapticFeedback.selectionClick());
        case Haptic.light:
          unawaited(HapticFeedback.lightImpact());
        case Haptic.medium:
          unawaited(HapticFeedback.mediumImpact());
        case Haptic.heavy:
          unawaited(HapticFeedback.heavyImpact());
      }
    } on Object catch (error) {
      AppLogger.d('Could not vibrate', error);
    }
  }

  /// Releases every player.
  Future<void> dispose() async {
    _ready = false;
    final List<AudioPlayer> players = <AudioPlayer>[..._pool];
    _pool.clear();
    for (final AudioPlayer player in players) {
      try {
        await player.dispose();
      } on Object catch (error) {
        AppLogger.d('Could not dispose an audio player', error);
      }
    }
  }
}
