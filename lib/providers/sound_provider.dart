import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/models/app_settings.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/providers/profile_provider.dart';
import 'package:scribble_guess/providers/session_providers.dart';
import 'package:scribble_guess/providers/settings_provider.dart';
import 'package:scribble_guess/services/sound_service.dart';

/// The sound player, kept in step with the player's preferences.
///
/// The two toggles are pushed onto the service rather than read back out of
/// this provider at each call site, because a sound is played from inside
/// listeners and gesture callbacks where there is no `WidgetRef` to hand and no
/// rebuild to hang a `watch` on. Pushing means the check happens inside
/// [SoundService.play] and every caller gets it for free.
///
/// The service is built once and survives both toggles moving, so flipping
/// sound off and on again does not tear down and rebuild the audio players.
final Provider<SoundService> soundServiceProvider = Provider<SoundService>(
  (Ref ref) {
    final SoundService service = SoundService();
    ref.listen<AppSettings>(
      settingsProvider,
      (AppSettings? _, AppSettings next) {
        service.soundEnabled = next.soundEnabled;
        service.hapticsEnabled = next.hapticsEnabled;
      },
      fireImmediately: true,
    );
    ref.onDispose(service.dispose);
    return service;
  },
);

/// How many seconds of a turn are counted down audibly.
const int _countdownFrom = 5;

/// Turns game events into sounds.
///
/// ## Why this is one provider and not a `play()` scattered through the screens
///
/// Almost every cue here is a *consequence of server state changing*, not of
/// something the local player did: somebody guessed, a letter was revealed, the
/// turn ended. Those arrive over the socket and land in `gameProvider` whether
/// or not the screen that would have played the sound is currently built — and
/// during a phase change it very often is not, because the router is busy
/// swapping lobby for game or game for results.
///
/// So the cues are attached to the state itself, once, above the router. A
/// sound then cannot be missed because a widget was mid-rebuild, and the rule
/// for what a given transition sounds like lives in one readable list rather
/// than being spread across five screens.
///
/// Watched by `ScribbleGuessApp` purely to keep it alive; it exposes nothing.
final Provider<void> gameSoundsProvider = Provider<void>((Ref ref) {
  final SoundService sound = ref.watch(soundServiceProvider);

  _listenToGame(ref, sound);
  _listenToClock(ref, sound);
  _listenToRoom(ref, sound);
  _listenToChat(ref, sound);
});

/// Guesses, hints and phase changes, all of which the server owns.
void _listenToGame(Ref ref, SoundService sound) {
  ref.listen<GameState>(gameProvider, (GameState? was, GameState now) {
    if (was == null) {
      return;
    }

    // Someone guessed. Compared only within a single turn: `correctGuesserIds`
    // is emptied when the next turn starts, and a stale comparison across that
    // boundary would either miss the first guess of the turn or replay the
    // whole previous list.
    final bool sameTurn = was.currentRound == now.currentRound &&
        was.turnIndex == now.turnIndex;
    if (sameTurn && now.correctGuesserIds.length > was.correctGuesserIds.length) {
      final List<String> fresh =
          now.correctGuesserIds.sublist(was.correctGuesserIds.length);
      sound.play(
        fresh.contains(ref.read(selfIdProvider))
            ? SoundEffect.correctSelf
            : SoundEffect.correctGuess,
      );
    }

    // A letter was revealed.
    if (sameTurn && now.hintIndices.length > was.hintIndices.length) {
      sound.play(SoundEffect.hint);
    }

    if (was.phase == now.phase) {
      return;
    }
    switch (now.phase) {
      // Only the drawer is being asked to do something here, and only they get
      // a sound. Everyone else is waiting, and a chime for waiting is noise.
      case GamePhase.wordSelection:
        if (now.isDrawer(ref.read(selfIdProvider))) {
          sound.play(SoundEffect.yourTurn);
        }
      case GamePhase.drawing:
        sound.play(SoundEffect.turnStart);
      // Nobody got it: the turn ended on the clock rather than on an answer,
      // and that deserves the buzzer rather than the cadence.
      case GamePhase.roundEnd:
        sound.play(
          now.correctGuesserIds.isEmpty
              ? SoundEffect.timeUp
              : SoundEffect.roundEnd,
        );
      case GamePhase.gameEnd:
        sound.play(SoundEffect.gameEnd);
      case GamePhase.lobby:
      case GamePhase.starting:
      case GamePhase.paused:
        break;
    }
  });
}

/// The last few seconds of a turn.
void _listenToClock(Ref ref, SoundService sound) {
  ref.listen<int?>(secondsRemainingProvider, (int? was, int? now) {
    // Only on a whole second actually elapsing. The clock provider ticks
    // several times a second so that the on-screen countdown is smooth, and
    // without this the last five seconds would be a rattle.
    if (was == null || now == null || now == was) {
      return;
    }
    if (now <= 0 || now > _countdownFrom) {
      return;
    }
    // Between turns the deadline belongs to a phase nobody is racing, so the
    // countdown would be counting down to nothing in particular.
    if (ref.read(gameProvider).phase != GamePhase.drawing) {
      return;
    }
    sound.play(SoundEffect.tick);
  });
}

/// Arrivals and departures.
void _listenToRoom(Ref ref, SoundService sound) {
  ref.listen<List<Player>>(playersProvider, (List<Player>? was, List<Player> now) {
    if (was == null || was.length == now.length) {
      return;
    }
    sound.play(
      now.length > was.length
          ? SoundEffect.playerJoined
          : SoundEffect.playerLeft,
    );
  });
}

/// Near misses.
///
/// The only cue that has to come from the transcript rather than from the game
/// state: "one letter away" is a judgement the server makes about a single
/// guess and reports to the player who made it, and it never lands in
/// `GameState` because nothing else needs to know.
void _listenToChat(Ref ref, SoundService sound) {
  String? lastSounded;

  ref.listen<List<ChatMessage>>(
    chatProvider,
    (List<ChatMessage>? was, List<ChatMessage> now) {
      if (now.isEmpty) {
        lastSounded = null;
        return;
      }
      // The newest line only, keyed by id rather than by list length: the
      // transcript is capped and drops its oldest line once full, so at the cap
      // a new message leaves the length unchanged.
      final ChatMessage latest = now.last;
      if (latest.id == lastSounded) {
        return;
      }
      lastSounded = latest.id;

      if (was != null &&
          latest.type == ChatMessageType.closeGuess &&
          latest.senderId == ref.read(selfIdProvider)) {
        sound.play(SoundEffect.closeGuess);
      }
    },
  );
}
