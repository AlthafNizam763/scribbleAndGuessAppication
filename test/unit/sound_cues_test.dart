import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/app_settings.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/repositories/settings_repository.dart';
import 'package:scribble_guess/services/sound_service.dart';

/// Which game events make which noise.
///
/// The mapping is the whole of this feature's behaviour and none of it shows up
/// on screen, so nothing else in the app would notice it rotting: a cue wired
/// to the wrong transition is silent in exactly the way a working one is.

/// A [SoundService] that records instead of playing.
///
/// Subclasses rather than reimplements an interface, so these tests are bound
/// to the same `play` the app calls. Nothing here reaches the platform: the
/// base constructor allocates no players, and [play] never delegates.
class RecordingSound extends SoundService {
  final List<SoundEffect> played = <SoundEffect>[];

  @override
  void play(SoundEffect effect) => played.add(effect);

  void clear() => played.clear();
}

/// Settings storage that keeps the last write in memory.
class MemorySettings implements SettingsRepository {
  AppSettings stored = AppSettings.defaults;

  @override
  Future<AppSettings> load() async => stored;

  @override
  Future<Result<void>> save(AppSettings settings) async {
    stored = settings;
    return const Ok<void>(null);
  }
}

/// The game state the container under test sees, writable by the test.
final StateProvider<GameState> _game =
    StateProvider<GameState>((Ref ref) => GameState.initial);

/// The room roster, writable by the test.
final StateProvider<List<Player>> _players =
    StateProvider<List<Player>>((Ref ref) => const <Player>[]);

/// The countdown, writable by the test.
final StateProvider<int?> _clock = StateProvider<int?>((Ref ref) => null);

/// A container with the sound listeners installed over state the test drives.
///
/// Every setter pumps before returning. Riverpod only marks a dependent dirty
/// when its source changes and recomputes it on the next scheduler pass, so
/// without that the listeners would not have run yet and every assertion here
/// would pass for the wrong reason — by finding nothing, having triggered
/// nothing.
class Harness {
  Harness() {
    container = ProviderContainer(
      overrides: <Override>[
        soundServiceProvider.overrideWithValue(sound),
        selfIdProvider.overrideWithValue(self),
        gameProvider.overrideWith((Ref ref) => ref.watch(_game)),
        playersProvider.overrideWith((Ref ref) => ref.watch(_players)),
        secondsRemainingProvider.overrideWith((Ref ref) => ref.watch(_clock)),
      ],
    );
    // Installs the listeners. None of them fires yet: each ignores its first
    // value, because the first value is the state the player joined into
    // rather than something that just happened to them.
    container.read(gameSoundsProvider);
  }

  /// The local player's id, as every cue that cares about "you" sees it.
  static const String self = 'me';

  final RecordingSound sound = RecordingSound();
  late final ProviderContainer container;

  /// What has been played since the last [clear].
  List<SoundEffect> get played => sound.played;

  void clear() => sound.clear();

  void dispose() => container.dispose();

  /// Pushes a game state, as the server would.
  Future<void> game({
    required GamePhase phase,
    int turnIndex = 0,
    String drawerId = 'them',
    List<String> guessers = const <String>[],
    List<int> hints = const <int>[],
  }) async {
    container.read(_game.notifier).state = GameState(
      roomCode: 'A7K9P',
      phase: phase,
      currentRound: 1,
      totalRounds: 3,
      turnIndex: turnIndex,
      drawerId: drawerId,
      correctGuesserIds: guessers,
      hintIndices: hints,
    );
    await container.pump();
  }

  /// Replaces the roster.
  Future<void> roster(List<Player> players) async {
    container.read(_players.notifier).state = players;
    await container.pump();
  }

  /// Advances the countdown to [seconds].
  Future<void> clock(int? seconds) async {
    container.read(_clock.notifier).state = seconds;
    await container.pump();
  }
}

Harness harness() {
  final Harness h = Harness();
  addTearDown(h.dispose);
  return h;
}

void main() {
  group('guesses', () {
    test('yours is louder than anybody else s', () async {
      final Harness h = harness();
      await h.game(phase: GamePhase.drawing);
      h.clear();

      await h.game(phase: GamePhase.drawing, guessers: <String>['someone']);
      expect(h.played, <SoundEffect>[SoundEffect.correctGuess]);

      h.clear();
      await h.game(
        phase: GamePhase.drawing,
        guessers: <String>['someone', Harness.self],
      );
      expect(h.played, <SoundEffect>[SoundEffect.correctSelf]);
    });

    // The list is emptied when the next turn begins. Comparing across that
    // boundary would read the reset as three players un-guessing, and then the
    // first real guess of the new turn as no change at all.
    test('the list resetting between turns is not a guess', () async {
      final Harness h = harness();
      await h.game(
        phase: GamePhase.drawing,
        guessers: <String>['a', 'b', Harness.self],
      );
      h.clear();

      await h.game(phase: GamePhase.drawing, turnIndex: 1);
      expect(h.played, isNot(contains(SoundEffect.correctSelf)));
      expect(h.played, isNot(contains(SoundEffect.correctGuess)));

      h.clear();
      await h.game(
        phase: GamePhase.drawing,
        turnIndex: 1,
        guessers: <String>['a'],
      );
      expect(h.played, <SoundEffect>[SoundEffect.correctGuess]);
    });

    test('a revealed letter sounds once per letter', () async {
      final Harness h = harness();
      await h.game(phase: GamePhase.drawing);
      h.clear();

      await h.game(phase: GamePhase.drawing, hints: <int>[2]);
      await h.game(phase: GamePhase.drawing, hints: <int>[2, 5]);
      expect(h.played, <SoundEffect>[SoundEffect.hint, SoundEffect.hint]);
    });
  });

  group('phases', () {
    test('only the drawer is told to pick a word', () async {
      final Harness h = harness();
      await h.game(phase: GamePhase.wordSelection);
      expect(h.played, isNot(contains(SoundEffect.yourTurn)));

      await h.game(phase: GamePhase.drawing);
      h.clear();
      await h.game(
        phase: GamePhase.wordSelection,
        turnIndex: 1,
        drawerId: Harness.self,
      );
      expect(h.played, <SoundEffect>[SoundEffect.yourTurn]);
    });

    // The difference between the cadence and the buzzer, and the only place
    // the two are told apart.
    test('a turn nobody guessed ends on the buzzer', () async {
      final Harness h = harness();
      await h.game(phase: GamePhase.drawing);
      h.clear();

      await h.game(phase: GamePhase.roundEnd);
      expect(h.played, <SoundEffect>[SoundEffect.timeUp]);

      // The guess lands on its own push and the turn ends on a later one,
      // which is the order the server sends them in.
      await h.game(phase: GamePhase.drawing, turnIndex: 1);
      await h.game(
        phase: GamePhase.drawing,
        turnIndex: 1,
        guessers: <String>[Harness.self],
      );
      h.clear();
      await h.game(
        phase: GamePhase.roundEnd,
        turnIndex: 1,
        guessers: <String>[Harness.self],
      );
      expect(h.played, <SoundEffect>[SoundEffect.roundEnd]);
    });

    // The two can also arrive together, when the guess is the last one needed
    // and the server ends the turn in the same push. Both cues belong, in this
    // order: the player is told they got it, and then that the turn is over.
    test('a guess that ends the turn sounds both, in that order', () async {
      final Harness h = harness();
      await h.game(phase: GamePhase.drawing);
      h.clear();

      await h.game(
        phase: GamePhase.roundEnd,
        guessers: <String>[Harness.self],
      );
      expect(
        h.played,
        <SoundEffect>[SoundEffect.correctSelf, SoundEffect.roundEnd],
      );
    });

    test('the end of the game has its own sound', () async {
      final Harness h = harness();
      await h.game(phase: GamePhase.roundEnd);
      h.clear();

      await h.game(phase: GamePhase.gameEnd);
      expect(h.played, <SoundEffect>[SoundEffect.gameEnd]);
    });

    test('a pause is silent', () async {
      final Harness h = harness();
      await h.game(phase: GamePhase.drawing);
      h.clear();

      await h.game(phase: GamePhase.paused);
      expect(h.played, isEmpty);
    });
  });

  group('the clock', () {
    test('ticks only over the last few seconds of a drawing turn', () async {
      final Harness h = harness();
      await h.game(phase: GamePhase.drawing);
      h.clear();

      for (final int second in <int>[30, 7, 6, 5, 4, 3, 2, 1, 0]) {
        await h.clock(second);
      }
      expect(h.played, List<SoundEffect>.filled(5, SoundEffect.tick));
    });

    // The deadline outlives the drawing phase, so without the phase check the
    // results screen would count down to nothing.
    test('does not tick once the turn is over', () async {
      final Harness h = harness();
      await h.game(phase: GamePhase.roundEnd);
      h.clear();

      for (final int second in <int>[5, 4, 3]) {
        await h.clock(second);
      }
      expect(h.played, isEmpty);
    });
  });

  group('the room', () {
    test('arrivals and departures are opposite sounds', () async {
      final Harness h = harness();
      await h.roster(const <Player>[Player(id: Harness.self)]);
      h.clear();

      await h.roster(
        const <Player>[Player(id: Harness.self), Player(id: 'them')],
      );
      expect(h.played, <SoundEffect>[SoundEffect.playerJoined]);

      h.clear();
      await h.roster(const <Player>[Player(id: Harness.self)]);
      expect(h.played, <SoundEffect>[SoundEffect.playerLeft]);
    });

    test('a roster that changes without growing or shrinking is silent',
        () async {
      final Harness h = harness();
      await h.roster(const <Player>[Player(id: Harness.self)]);
      h.clear();

      await h.roster(const <Player>[Player(id: Harness.self, score: 40)]);
      expect(h.played, isEmpty);
    });
  });

  group('the settings', () {
    /// A container with the real settings notifier over in-memory storage.
    ProviderContainer settingsHarness() {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          bootstrapSettingsProvider.overrideWithValue(AppSettings.defaults),
          settingsRepositoryProvider.overrideWithValue(MemorySettings()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    // The bug this whole feature began as: the toggle wrote a preference that
    // nothing ever read.
    test('both toggles reach the service', () async {
      final ProviderContainer container = settingsHarness();
      final SoundService service = container.read(soundServiceProvider);
      expect(service.soundEnabled, isTrue);
      expect(service.hapticsEnabled, isTrue);

      await container.read(settingsProvider.notifier).setSoundEnabled(false);
      expect(service.soundEnabled, isFalse);
      expect(service.hapticsEnabled, isTrue);

      await container.read(settingsProvider.notifier).setHapticsEnabled(false);
      expect(service.hapticsEnabled, isFalse);

      await container.read(settingsProvider.notifier).setSoundEnabled(true);
      expect(service.soundEnabled, isTrue);
    });

    test('the service survives a toggle rather than being rebuilt', () async {
      final ProviderContainer container = settingsHarness();
      final SoundService first = container.read(soundServiceProvider);

      await container.read(settingsProvider.notifier).setSoundEnabled(false);
      expect(container.read(soundServiceProvider), same(first));
    });
  });

  group('the asset table', () {
    /// Every folder the sound system is allowed to read from.
    ///
    /// The shared set, plus one per game. A folder that appears in the enum
    /// and not here is a folder nobody declared in `pubspec.yaml`, which ships
    /// no files at all and fails silently at runtime — the effect simply never
    /// plays. That is the failure this list exists to turn into a red test.
    const Set<String> folders = <String>{
      'sounds',
      'kazhutha/audio',
      'bluff_bar/audio',
      'space_mystery/audio',
      'ludo/audio',
    };

    test('every effect names a distinct file in a declared folder', () {
      final Set<String> paths = <String>{
        for (final SoundEffect effect in SoundEffect.values) effect.asset,
      };

      // Distinct *paths*, not distinct file names: each game has its own
      // `click`, and they are different sounds in different folders. Before
      // the enum carried a folder they would have collided.
      expect(paths, hasLength(SoundEffect.values.length));

      for (final SoundEffect effect in SoundEffect.values) {
        expect(folders, contains(effect.folder), reason: effect.name);
        expect(effect.asset, startsWith('${effect.folder}/'));
        expect(effect.asset, endsWith('.wav'));
      }
    });

    test('keeps the shared set separate from the games', () {
      // A screen outside a game can only play the shared set, so anything
      // that drifted into it would be unplayable from the lobby — and a game
      // sound that lost its folder would be looked for in `assets/sounds`,
      // where it does not exist.
      final Iterable<SoundEffect> shared =
          SoundEffect.values.where((SoundEffect e) => e.isShared);

      expect(shared, isNotEmpty);
      for (final SoundEffect effect in shared) {
        expect(effect.folder, 'sounds');
      }
    });
  });
}
