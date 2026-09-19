// Synthesizes every sound effect in `assets/sounds/` from the score data below.
//
//   dart run tool/generate_sound_assets.dart
//
// A build tool, like `generate_brand_assets.dart` next to it, and written for
// the same reason: the game's audio is checked in, but it is *described* here
// rather than being a folder of binaries nobody can diff. Changing the pitch of
// the correct-guess arpeggio is a one-line edit followed by a re-run, not a
// trip through an audio editor.
//
// Plain Dart, no Flutter: synthesis is arithmetic over a sample buffer, so
// `dart run` is enough and this never needs a Skia canvas the way the brand
// assets do.
//
// The palette is deliberately chiptune — short triangle and square blips with
// a fast exponential decay. It suits a game drawn in wobbly pencil, and it
// keeps every file a couple of kilobytes, which matters because these ship
// inside the bundle and several of them fire in the same second.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Samples per second. 22.05 kHz is half CD rate: inaudible for blips whose
/// highest partial sits near 4 kHz, and it halves the bundle cost.
const int _sampleRate = 22050;

/// Peak amplitude every finished file is normalised to.
///
/// Short of 1.0 so that the 16-bit conversion cannot round up into a clip, and
/// so two effects firing together — a hint landing as someone guesses — still
/// have headroom to sum without distorting.
const double _peak = 0.82;

/// Length of the fade applied to the tail of every file, in seconds.
///
/// A waveform cut off mid-cycle ends on a vertical step, which a speaker
/// reproduces as an audible click. 5 ms of ramp costs nothing and removes it.
const double _tailFade = 0.005;

// --------------------------------------------------------------- waveforms ---

/// A periodic waveform sampled at [phase], which runs 0..1 over one cycle.
typedef Wave = double Function(double phase);

/// A triangle, the workhorse here: it carries odd harmonics like a square but
/// they fall away much faster, so it reads as "retro" without being shrill.
double _triangle(double phase) {
  final double t = phase % 1.0;
  return t < 0.5 ? 4 * t - 1 : 3 - 4 * t;
}

/// A square at 25% duty rather than 50%, which is thinner and more nasal — the
/// classic lead voice, and distinct enough from [_triangle] that layering the
/// two reads as two instruments.
double _square(double phase) => (phase % 1.0) < 0.25 ? 1.0 : -1.0;

// ------------------------------------------------------------------- notes ---

/// Semitone offsets of the natural notes from C, for [_freq].
const Map<String, int> _semitones = <String, int>{
  'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11,
};

/// Frequency of scientific pitch [name] — `'C5'`, `'F#4'`, `'Bb3'` — in Hz.
double _freq(String name) {
  final int octave = int.parse(name.substring(name.length - 1));
  final String pitch = name.substring(0, name.length - 1);
  int semitone = _semitones[pitch[0]]!;
  if (pitch.length > 1) {
    semitone += pitch[1] == '#' ? 1 : -1;
  }
  // A4 = 440 Hz sits 57 semitones above C0.
  return 440 * math.pow(2, (octave * 12 + semitone - 57) / 12).toDouble();
}

/// One note in a score.
class _Note {
  const _Note(
    this.pitch, {
    required this.at,
    required this.hold,
    this.wave = _triangle,
    this.gain = 1.0,
    this.decay = 9.0,
    this.bendTo,
  });

  /// Scientific pitch name, e.g. `'C5'`.
  final String pitch;

  /// When the note starts, in seconds from the beginning of the file.
  final double at;

  /// How long the note rings, in seconds.
  final double hold;

  /// Timbre.
  final Wave wave;

  /// Relative loudness before the file is normalised.
  final double gain;

  /// Exponential decay rate. Higher is percussive; ~2 is a sustained tone.
  final double decay;

  /// Pitch to glide to across [hold], for a slide. Null holds [pitch].
  final String? bendTo;
}

/// Renders [notes] into a normalised mono buffer.
Float64List _render(List<_Note> notes) {
  final double end = notes
      .map((_Note n) => n.at + n.hold)
      .reduce((double a, double b) => a > b ? a : b);
  final int total = (end * _sampleRate).ceil();
  final Float64List out = Float64List(total);

  for (final _Note note in notes) {
    final double from = _freq(note.pitch);
    final double to = note.bendTo == null ? from : _freq(note.bendTo!);
    final int start = (note.at * _sampleRate).floor();
    final int length = (note.hold * _sampleRate).ceil();

    // Phase is accumulated rather than computed from absolute time, because a
    // bend changes the frequency every sample and `f * t` would jump.
    double phase = 0;
    for (int i = 0; i < length && start + i < total; i++) {
      final double progress = i / length;
      final double hz = from + (to - from) * progress;
      final double seconds = i / _sampleRate;

      // 3 ms of attack, then an exponential tail. The attack is what stops the
      // note itself from starting on a step.
      const double attack = 0.003;
      final double envelope = seconds < attack
          ? seconds / attack
          : math.exp(-note.decay * (seconds - attack));

      out[start + i] += note.wave(phase) * envelope * note.gain;
      phase += hz / _sampleRate;
    }
  }

  // Fade the tail, then normalise to a fixed peak so no effect is noticeably
  // louder than another regardless of how many notes it stacks.
  final int fade = (_tailFade * _sampleRate).round();
  for (int i = 0; i < fade && i < total; i++) {
    out[total - 1 - i] *= i / fade;
  }
  double loudest = 0;
  for (final double sample in out) {
    loudest = math.max(loudest, sample.abs());
  }
  if (loudest > 0) {
    final double scale = _peak / loudest;
    for (int i = 0; i < total; i++) {
      out[i] *= scale;
    }
  }
  return out;
}

/// Wraps [samples] in a 16-bit mono PCM WAVE container.
Uint8List _wav(Float64List samples) {
  final int dataBytes = samples.length * 2;
  final ByteData out = ByteData(44 + dataBytes);
  int cursor = 0;

  void ascii(String tag) {
    for (final int code in tag.codeUnits) {
      out.setUint8(cursor++, code);
    }
  }

  void u32(int value) {
    out.setUint32(cursor, value, Endian.little);
    cursor += 4;
  }

  void u16(int value) {
    out.setUint16(cursor, value, Endian.little);
    cursor += 2;
  }

  ascii('RIFF');
  u32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16); // PCM header length
  u16(1); // PCM, uncompressed
  u16(1); // mono
  u32(_sampleRate);
  u32(_sampleRate * 2); // byte rate: rate * channels * bytes per sample
  u16(2); // block align
  u16(16); // bits per sample
  ascii('data');
  u32(dataBytes);

  for (final double sample in samples) {
    final int value = (sample.clamp(-1.0, 1.0) * 32767).round();
    out.setInt16(cursor, value, Endian.little);
    cursor += 2;
  }
  return out.buffer.asUint8List();
}

// ------------------------------------------------------------------ scores ---

/// Every effect the game can play, keyed by the file it is written to.
///
/// Keep this in step with `SoundEffect` in `lib/services/sound_service.dart`:
/// the enum names the asset, and a name here with no counterpart there is a
/// file that ships and never plays.
const Map<String, List<_Note>> _scores = <String, List<_Note>>{
  // A dry, quiet click under a button. It fires constantly, so it is the one
  // sound that must never draw attention to itself.
  'tap': <_Note>[
    _Note('D6', at: 0, hold: 0.05, gain: 0.45, decay: 60),
  ],

  // Someone else got it: a plain major triad, pleasant but unremarkable,
  // because in a full room this can fire five times in twenty seconds.
  'correct_guess': <_Note>[
    _Note('C5', at: 0.00, hold: 0.13, decay: 14),
    _Note('E5', at: 0.05, hold: 0.13, decay: 14),
    _Note('G5', at: 0.10, hold: 0.20, decay: 10),
  ],

  // You got it. Deliberately a bigger event than the line above: the same
  // triad carried an octave higher, on the brighter square lead, with the root
  // doubled underneath so it lands with some weight.
  'correct_self': <_Note>[
    _Note('C5', at: 0.00, hold: 0.12, wave: _square, gain: 0.7, decay: 16),
    _Note('E5', at: 0.06, hold: 0.12, wave: _square, gain: 0.7, decay: 16),
    _Note('G5', at: 0.12, hold: 0.12, wave: _square, gain: 0.7, decay: 16),
    _Note('C6', at: 0.18, hold: 0.34, wave: _square, gain: 0.9, decay: 7),
    _Note('C4', at: 0.18, hold: 0.34, gain: 0.5, decay: 7),
  ],

  // One letter away. An unresolved whole step — it asks a question rather than
  // answering one, which is exactly what a near miss is.
  'close_guess': <_Note>[
    _Note('F5', at: 0.00, hold: 0.10, gain: 0.75, decay: 20),
    _Note('E5', at: 0.07, hold: 0.16, gain: 0.75, decay: 14),
  ],

  // A letter was revealed. Barely there: information, not an event.
  'hint': <_Note>[
    _Note('A5', at: 0, hold: 0.09, gain: 0.5, decay: 28),
  ],

  // Arrivals rise, departures fall. Same two notes, opposite order, so the two
  // are unmistakable without either needing to be loud.
  'player_joined': <_Note>[
    _Note('G4', at: 0.00, hold: 0.09, gain: 0.6, decay: 22),
    _Note('C5', at: 0.06, hold: 0.15, gain: 0.6, decay: 16),
  ],
  'player_left': <_Note>[
    _Note('C5', at: 0.00, hold: 0.09, gain: 0.6, decay: 22),
    _Note('G4', at: 0.06, hold: 0.15, gain: 0.6, decay: 16),
  ],

  // Your turn to pick a word. This one is allowed to nag: it is the only cue
  // in the game that asks the player to do something before a timer runs out,
  // so it is a repeated fifth rather than a single blip.
  'your_turn': <_Note>[
    _Note('C5', at: 0.00, hold: 0.14, wave: _square, gain: 0.7, decay: 14),
    _Note('G5', at: 0.00, hold: 0.14, gain: 0.5, decay: 14),
    _Note('C5', at: 0.18, hold: 0.14, wave: _square, gain: 0.7, decay: 14),
    _Note('G5', at: 0.18, hold: 0.28, gain: 0.5, decay: 9),
  ],

  // The drawing starts. A quick upward run: go.
  'turn_start': <_Note>[
    _Note('G4', at: 0.00, hold: 0.08, gain: 0.7, decay: 24),
    _Note('C5', at: 0.05, hold: 0.08, gain: 0.7, decay: 24),
    _Note('E5', at: 0.10, hold: 0.22, gain: 0.8, decay: 11),
  ],

  // The turn is over. The mirror of turn_start, resolving downward onto the
  // root so the round feels closed rather than interrupted.
  'round_end': <_Note>[
    _Note('E5', at: 0.00, hold: 0.10, gain: 0.7, decay: 18),
    _Note('C5', at: 0.08, hold: 0.10, gain: 0.7, decay: 18),
    _Note('G4', at: 0.16, hold: 0.30, gain: 0.8, decay: 8),
  ],

  // The whole game is over. The longest sound in the set by some way, and the
  // only one built on a held chord: a run up the triad, then C major ringing
  // across three octaves.
  'game_end': <_Note>[
    _Note('C5', at: 0.00, hold: 0.10, wave: _square, gain: 0.6, decay: 20),
    _Note('E5', at: 0.09, hold: 0.10, wave: _square, gain: 0.6, decay: 20),
    _Note('G5', at: 0.18, hold: 0.10, wave: _square, gain: 0.6, decay: 20),
    _Note('C6', at: 0.27, hold: 0.12, wave: _square, gain: 0.7, decay: 18),
    _Note('C4', at: 0.40, hold: 0.90, gain: 0.55, decay: 3.0),
    _Note('E5', at: 0.40, hold: 0.90, gain: 0.45, decay: 3.2),
    _Note('G5', at: 0.40, hold: 0.90, gain: 0.45, decay: 3.2),
    _Note('C6', at: 0.40, hold: 0.90, wave: _square, gain: 0.5, decay: 3.0),
  ],

  // The clock, in the last few seconds. Quieter than `tap`, because it fires
  // once a second and the player is trying to concentrate.
  'tick': <_Note>[
    _Note('A5', at: 0, hold: 0.04, gain: 0.32, decay: 70),
  ],

  // Nobody guessed and the clock ran out. Two detuned low squares beating
  // against each other, bent downward: the one genuinely unpleasant sound
  // here, which is the point.
  'time_up': <_Note>[
    _Note('G3', at: 0, hold: 0.42, wave: _square, gain: 0.8, decay: 3.5,
        bendTo: 'D3'),
    _Note('G#3', at: 0, hold: 0.42, wave: _square, gain: 0.6, decay: 3.5,
        bendTo: 'D#3'),
  ],
};

// ------------------------------------------------------------- game scores ---

/// Per-game effects, keyed by the folder they are written to.
///
/// ## Why these are not in `_scores`
///
/// Because they are not the app's sounds, they are a *place's*. The shared set
/// above has to work under every screen in the product, which is why it is
/// neutral chiptune. These do not: a card being drawn should sound like a card
/// being drawn at that particular table, the bar should sound like a room with
/// a low ceiling, and the Meridian should sound like a metal box in space.
/// Keeping them apart means a game can have a voice without the lobby
/// inheriting it.
///
/// ## Why they are still synthesised
///
/// Same reason the rest of them are, stated in the header: art that is
/// described can be diffed, reviewed and adjusted, and a folder of binaries
/// cannot. It also keeps them tiny — every file here is a few kilobytes, which
/// matters when thirty-odd of them ship inside the bundle.
///
/// ## The one thing that is *not* here
///
/// Looping ambience. A bar's room tone and a ship's hum want to run for
/// minutes, and a minute of 22 kHz PCM is well over a megabyte — the exact
/// thing the brief says not to ship. So `ambience` in both games is a short
/// *sting*: a couple of seconds played on arrival to establish the place, and
/// then silence. A genuine bed would need a streaming loop and a compressed
/// format, which is a different feature.
const Map<String, Map<String, List<_Note>>> _gameScores =
    <String, Map<String, List<_Note>>>{
  // --------------------------------------------------------------- Kazhutha
  //
  // A warm, wooden card room. Everything here is short, mid-register and
  // slightly soft-edged: cards on baize do not click, they whisper.
  'kazhutha': <String, List<_Note>>{
    // A card sliding out of somebody's hand. Two very short noisy blips a
    // few milliseconds apart, which is what a card leaving a fan sounds like.
    'card_draw': <_Note>[
      _Note('A6', at: 0.000, hold: 0.035, wave: _square, gain: 0.30, decay: 90),
      _Note('E6', at: 0.030, hold: 0.045, wave: _square, gain: 0.22, decay: 70),
    ],

    // And landing. Lower and blunter than the draw, because the table absorbs
    // it — the pair of them together is the whole gesture.
    'card_place': <_Note>[
      _Note('D4', at: 0.000, hold: 0.060, gain: 0.55, decay: 55),
      _Note('A3', at: 0.010, hold: 0.080, gain: 0.35, decay: 40),
    ],

    // A riffle. Six descending ticks in forty milliseconds, which reads as a
    // deck being run rather than as six separate sounds.
    'card_shuffle': <_Note>[
      _Note('B5', at: 0.000, hold: 0.030, wave: _square, gain: 0.22, decay: 95),
      _Note('A5', at: 0.035, hold: 0.030, wave: _square, gain: 0.22, decay: 95),
      _Note('G5', at: 0.070, hold: 0.030, wave: _square, gain: 0.22, decay: 95),
      _Note('A5', at: 0.105, hold: 0.030, wave: _square, gain: 0.20, decay: 95),
      _Note('G5', at: 0.140, hold: 0.030, wave: _square, gain: 0.18, decay: 95),
      _Note('E5', at: 0.175, hold: 0.050, wave: _square, gain: 0.16, decay: 70),
    ],

    // Your go. A rising fourth — the most "attention" two notes can be
    // without being an alarm.
    'turn_change': <_Note>[
      _Note('G4', at: 0.00, hold: 0.10, gain: 0.7, decay: 16),
      _Note('C5', at: 0.07, hold: 0.16, gain: 0.8, decay: 12),
    ],

    // A pair going down: a bright, satisfied major third. This fires often,
    // so it stays small.
    'pair_made': <_Note>[
      _Note('E5', at: 0.00, hold: 0.09, gain: 0.6, decay: 20),
      _Note('G#5', at: 0.05, hold: 0.14, gain: 0.6, decay: 16),
    ],

    // The donkey, revealed. A comedy slide down a minor third and then a
    // flat, deflated tone — the sound of the whole table laughing at somebody.
    'donkey_reveal': <_Note>[
      _Note('C5', at: 0.00, hold: 0.30, wave: _square, gain: 0.8, decay: 4,
          bendTo: 'A4'),
      _Note('A4', at: 0.26, hold: 0.45, wave: _square, gain: 0.7, decay: 3.2,
          bendTo: 'F4'),
      _Note('F3', at: 0.50, hold: 0.55, gain: 0.5, decay: 3),
    ],

    'win': <_Note>[
      _Note('C5', at: 0.00, hold: 0.14, gain: 0.8, decay: 12),
      _Note('E5', at: 0.09, hold: 0.14, gain: 0.8, decay: 12),
      _Note('G5', at: 0.18, hold: 0.14, gain: 0.8, decay: 12),
      _Note('C6', at: 0.27, hold: 0.40, gain: 0.9, decay: 5),
    ],

    'lose': <_Note>[
      _Note('G4', at: 0.00, hold: 0.16, gain: 0.7, decay: 10),
      _Note('E4', at: 0.12, hold: 0.16, gain: 0.7, decay: 10),
      _Note('C4', at: 0.24, hold: 0.42, gain: 0.7, decay: 4.5),
    ],

    // Softer than the shared `tap`: this is a wooden table, not a phone.
    'click': <_Note>[
      _Note('A5', at: 0, hold: 0.045, gain: 0.40, decay: 70),
    ],
  },

  // -------------------------------------------------------------- Bluff Bar
  //
  // Low, close and a little unpleasant. Almost everything is under C4 and uses
  // the square wave, which is thinner and more nasal — it sits where a room
  // with a low ceiling sits.
  'bluff_bar': <String, List<_Note>>{
    // Cards onto wood, five of them, uneven. The unevenness is the point: a
    // metronome reads as a machine dealing.
    'deal': <_Note>[
      _Note('F3', at: 0.000, hold: 0.055, gain: 0.5, decay: 55),
      _Note('E3', at: 0.075, hold: 0.055, gain: 0.45, decay: 55),
      _Note('F3', at: 0.145, hold: 0.055, gain: 0.5, decay: 55),
      _Note('D3', at: 0.230, hold: 0.055, gain: 0.42, decay: 55),
      _Note('F3', at: 0.300, hold: 0.070, gain: 0.48, decay: 45),
    ],

    // The room. A low drone with a slow beat against a neighbour a semitone
    // off, which is what makes it sound like a space rather than a note.
    'ambience': <_Note>[
      _Note('C2', at: 0, hold: 1.60, gain: 0.55, decay: 1.1),
      _Note('C#2', at: 0, hold: 1.60, gain: 0.30, decay: 1.1),
      _Note('G2', at: 0.20, hold: 1.30, gain: 0.22, decay: 1.4),
    ],

    // Somebody calls a liar. Sharp, upward, and rude.
    'bluff_call': <_Note>[
      _Note('A3', at: 0.00, hold: 0.10, wave: _square, gain: 0.8, decay: 18,
          bendTo: 'E4'),
      _Note('E4', at: 0.08, hold: 0.22, wave: _square, gain: 0.9, decay: 9),
    ],

    // Cards turning over. Three rising ticks, one per card, then the verdict
    // lands on whatever plays next.
    'reveal': <_Note>[
      _Note('D4', at: 0.00, hold: 0.06, wave: _square, gain: 0.5, decay: 40),
      _Note('F4', at: 0.14, hold: 0.06, wave: _square, gain: 0.55, decay: 40),
      _Note('A4', at: 0.28, hold: 0.14, wave: _square, gain: 0.7, decay: 16),
    ],

    // The pause before a glass is drunk. A tritone, held — the most
    // unresolved interval there is, which is exactly the feeling.
    'tension': <_Note>[
      _Note('C3', at: 0, hold: 0.90, wave: _square, gain: 0.55, decay: 1.8),
      _Note('F#3', at: 0, hold: 0.90, wave: _square, gain: 0.45, decay: 1.8),
    ],

    // That was the bad glass. A hard drop with no resolution at all.
    'elimination': <_Note>[
      _Note('A3', at: 0.00, hold: 0.55, wave: _square, gain: 0.9, decay: 3,
          bendTo: 'D2'),
      _Note('D2', at: 0.40, hold: 0.60, gain: 0.7, decay: 2.4),
    ],

    'win': <_Note>[
      _Note('D4', at: 0.00, hold: 0.16, wave: _square, gain: 0.7, decay: 10),
      _Note('A4', at: 0.11, hold: 0.16, wave: _square, gain: 0.75, decay: 10),
      _Note('D5', at: 0.22, hold: 0.45, gain: 0.85, decay: 4),
    ],

    'lose': <_Note>[
      _Note('D4', at: 0.00, hold: 0.20, wave: _square, gain: 0.65, decay: 8),
      _Note('Ab3', at: 0.16, hold: 0.20, wave: _square, gain: 0.6, decay: 8),
      _Note('D3', at: 0.34, hold: 0.55, gain: 0.6, decay: 3),
    ],

    'click': <_Note>[
      _Note('E4', at: 0, hold: 0.04, wave: _square, gain: 0.35, decay: 80),
    ],
  },

  // ---------------------------------------------------------- Space Mystery
  //
  // Bright and synthetic rather than grim. The brief is a *playful* spaceship,
  // and a social deduction game that sounds like a horror game stops being fun
  // about ten seconds in — so the dread is carried by two sounds (emergency,
  // sabotage) and everything else is cheerful instrumentation.
  'space_mystery': <String, List<_Note>>{
    // The ship. A high shimmer over a low hum: the two together read as a
    // pressurised metal box, which is what it is.
    'ambience': <_Note>[
      _Note('G2', at: 0.00, hold: 1.70, gain: 0.5, decay: 1.0),
      _Note('D4', at: 0.10, hold: 1.40, gain: 0.16, decay: 1.3),
      _Note('G5', at: 0.30, hold: 1.10, gain: 0.08, decay: 1.6),
    ],

    // A console finishing. A clean, high, two-note confirm — the single most
    // frequent sound in the game, so it is short and never triumphant.
    'task_complete': <_Note>[
      _Note('E6', at: 0.00, hold: 0.08, gain: 0.55, decay: 24),
      _Note('B6', at: 0.06, hold: 0.14, gain: 0.5, decay: 16),
    ],

    // The alarm. Two cycles of a rising-falling klaxon on the square wave,
    // which is about as close to a real alarm as two oscillators get.
    'emergency': <_Note>[
      _Note('A4', at: 0.00, hold: 0.30, wave: _square, gain: 0.9, decay: 2.2,
          bendTo: 'E5'),
      _Note('E5', at: 0.28, hold: 0.30, wave: _square, gain: 0.9, decay: 2.2,
          bendTo: 'A4'),
      _Note('A4', at: 0.56, hold: 0.30, wave: _square, gain: 0.8, decay: 2.2,
          bendTo: 'E5'),
      _Note('E5', at: 0.84, hold: 0.36, wave: _square, gain: 0.8, decay: 2.0,
          bendTo: 'A4'),
    ],

    // Everybody to the table. A descending call, brisk and official.
    'meeting': <_Note>[
      _Note('D5', at: 0.00, hold: 0.14, gain: 0.8, decay: 12),
      _Note('A4', at: 0.12, hold: 0.14, gain: 0.8, decay: 12),
      _Note('D4', at: 0.24, hold: 0.30, gain: 0.7, decay: 6),
    ],

    // A vote landing. One flat, neutral tone — it must not sound like
    // approval, because half the time it is not.
    'voting': <_Note>[
      _Note('A4', at: 0, hold: 0.12, wave: _square, gain: 0.5, decay: 20),
    ],

    // The last few seconds. One tick; the UI repeats it.
    'countdown': <_Note>[
      _Note('C6', at: 0, hold: 0.05, wave: _square, gain: 0.45, decay: 60),
    ],

    // Somebody is gone. A long fall into nothing, which is also the airlock.
    'elimination': <_Note>[
      _Note('E5', at: 0.00, hold: 0.70, wave: _square, gain: 0.8, decay: 2.4,
          bendTo: 'E3'),
      _Note('E3', at: 0.55, hold: 0.50, gain: 0.55, decay: 2.6),
    ],

    // Something has been pulled. A dirty low pulse — the only genuinely
    // unpleasant sound in the game, and it is meant to be.
    'sabotage': <_Note>[
      _Note('F2', at: 0.00, hold: 0.45, wave: _square, gain: 0.85, decay: 3.4),
      _Note('B2', at: 0.06, hold: 0.45, wave: _square, gain: 0.55, decay: 3.4),
      _Note('F2', at: 0.34, hold: 0.45, wave: _square, gain: 0.7, decay: 3.4),
    ],

    'success': <_Note>[
      _Note('G4', at: 0.00, hold: 0.13, gain: 0.75, decay: 13),
      _Note('B4', at: 0.08, hold: 0.13, gain: 0.75, decay: 13),
      _Note('D5', at: 0.16, hold: 0.13, gain: 0.75, decay: 13),
      _Note('G5', at: 0.24, hold: 0.42, gain: 0.85, decay: 4.5),
    ],

    'failure': <_Note>[
      _Note('Eb5', at: 0.00, hold: 0.18, wave: _square, gain: 0.7, decay: 8),
      _Note('B4', at: 0.14, hold: 0.18, wave: _square, gain: 0.7, decay: 8),
      _Note('Eb4', at: 0.30, hold: 0.55, gain: 0.7, decay: 3),
    ],

    'click': <_Note>[
      _Note('B5', at: 0, hold: 0.04, wave: _square, gain: 0.38, decay: 80),
    ],
  },

  // ------------------------------------------------------------------- Ludo
  //
  // Bright, plastic and family-friendly. Everything is major, everything is
  // short, nothing is threatening — it is a board game on a kitchen table.
  'ludo': <String, List<_Note>>{
    // Dice in a cup. Four irregular ticks, then the throw.
    'dice_roll': <_Note>[
      _Note('D5', at: 0.000, hold: 0.030, wave: _square, gain: 0.30, decay: 90),
      _Note('A5', at: 0.055, hold: 0.030, wave: _square, gain: 0.28, decay: 90),
      _Note('F5', at: 0.100, hold: 0.030, wave: _square, gain: 0.30, decay: 90),
      _Note('C5', at: 0.160, hold: 0.030, wave: _square, gain: 0.26, decay: 90),
      _Note('G4', at: 0.220, hold: 0.090, gain: 0.55, decay: 30),
    ],

    // A token stepping. One blip; the board repeats it per square, which is
    // what makes a six sound like a six.
    'token_move': <_Note>[
      _Note('E5', at: 0, hold: 0.045, gain: 0.45, decay: 60),
    ],

    // Sending somebody home. Cheerfully mean: a bright rise and a rude drop.
    'token_capture': <_Note>[
      _Note('C5', at: 0.00, hold: 0.09, wave: _square, gain: 0.7, decay: 22),
      _Note('G5', at: 0.07, hold: 0.09, wave: _square, gain: 0.7, decay: 22),
      _Note('C4', at: 0.16, hold: 0.28, gain: 0.7, decay: 7),
    ],

    // Reaching a star. A small, reassuring two-note lift.
    'safe_tile': <_Note>[
      _Note('A5', at: 0.00, hold: 0.07, gain: 0.5, decay: 26),
      _Note('E6', at: 0.05, hold: 0.12, gain: 0.5, decay: 18),
    ],

    // A token home. Higher and fuller than the safe tile; this one counts.
    'home': <_Note>[
      _Note('G5', at: 0.00, hold: 0.10, gain: 0.7, decay: 16),
      _Note('B5', at: 0.07, hold: 0.10, gain: 0.7, decay: 16),
      _Note('D6', at: 0.14, hold: 0.26, gain: 0.8, decay: 7),
    ],

    'victory': <_Note>[
      _Note('C5', at: 0.00, hold: 0.12, gain: 0.8, decay: 13),
      _Note('E5', at: 0.08, hold: 0.12, gain: 0.8, decay: 13),
      _Note('G5', at: 0.16, hold: 0.12, gain: 0.8, decay: 13),
      _Note('C6', at: 0.24, hold: 0.12, gain: 0.85, decay: 13),
      _Note('E6', at: 0.32, hold: 0.12, gain: 0.85, decay: 13),
      _Note('G6', at: 0.40, hold: 0.45, gain: 0.9, decay: 4.5),
    ],

    'turn_change': <_Note>[
      _Note('F4', at: 0.00, hold: 0.09, gain: 0.6, decay: 18),
      _Note('Bb4', at: 0.06, hold: 0.16, gain: 0.7, decay: 12),
    ],

    'click': <_Note>[
      _Note('C6', at: 0, hold: 0.04, gain: 0.40, decay: 80),
    ],
  },
};

// -------------------------------------------------------------------- main ---

/// Renders one folder of scores and reports what it wrote.
int _writeFolder(String path, Map<String, List<_Note>> scores) {
  final Directory out = Directory(path);
  if (!out.existsSync()) {
    out.createSync(recursive: true);
  }

  int bytes = 0;
  for (final MapEntry<String, List<_Note>> entry in scores.entries) {
    final Uint8List wav = _wav(_render(entry.value));
    File('${out.path}/${entry.key}.wav').writeAsBytesSync(wav);
    bytes += wav.length;
    final String size = (wav.length / 1024).toStringAsFixed(1);
    stdout.writeln('  ${entry.key.padRight(18)} ${size.padLeft(6)} KB  $path');
  }
  return bytes;
}

Future<void> main() async {
  int bytes = _writeFolder('assets/sounds', _scores);
  int count = _scores.length;

  // Each game's own voice, in its own folder — which is also where its art
  // would go. See the asset layout in `pubspec.yaml`.
  for (final MapEntry<String, Map<String, List<_Note>>> game in _gameScores.entries) {
    bytes += _writeFolder('assets/${game.key}/audio', game.value);
    count += game.value.length;
  }

  stdout.writeln(
    'Wrote $count sounds (${(bytes / 1024).toStringAsFixed(1)} KB total).',
  );
}
