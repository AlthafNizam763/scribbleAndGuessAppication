import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// Levels, XP and achievements, as the server reports them.
///
/// ## They are read-only, and more strictly so than most models here
///
/// None of these has a `toJson`, and there is no endpoint that would accept
/// one. XP is computed by the server from facts only it holds, achievements
/// unlock as a consequence, and a client that could serialise either could be
/// asked to. The app never adds up XP itself and never decides that a
/// threshold was crossed — it renders what it is told.
///
/// Every `fromJson` tolerates a malformed or missing field rather than
/// throwing, in the same style as the rest of `lib/models`: a trophy case that
/// drops one bad row still renders.

/// Where a player sits on the level curve.
class PlayerLevel extends Equatable {
  /// Creates a level.
  const PlayerLevel({
    this.level = 1,
    this.title = '',
    this.xp = 0,
    this.levelStartXp = 0,
    this.nextLevelXp,
    this.xpIntoLevel = 0,
    this.xpForNextLevel,
    this.progress = 0,
    this.isMaxLevel = false,
  });

  /// Builds a level from a decoded JSON map. Never throws.
  factory PlayerLevel.fromJson(Map<String, dynamic> json) => PlayerLevel(
        level: asInt(json['level'], 1),
        title: asString(json['title']),
        xp: asInt(json['xp']),
        levelStartXp: asInt(json['levelStartXp']),
        nextLevelXp:
            json['nextLevelXp'] == null ? null : asInt(json['nextLevelXp']),
        xpIntoLevel: asInt(json['xpIntoLevel']),
        xpForNextLevel:
            json['xpForNextLevel'] == null ? null : asInt(json['xpForNextLevel']),
        progress: asDouble(json['progress']).clamp(0, 1).toDouble(),
        isMaxLevel: asBool(json['isMaxLevel']),
      );

  /// The current level, 1 at minimum.
  final int level;

  /// The tier name, e.g. `Artist`.
  final String title;

  /// Lifetime XP.
  final int xp;

  /// Total XP at which this level began.
  final int levelStartXp;

  /// Total XP at which the next level begins, or null at the cap.
  final int? nextLevelXp;

  /// XP earned inside this level.
  final int xpIntoLevel;

  /// How much XP this level spans, or null at the cap.
  final int? xpForNextLevel;

  /// 0..1 through the current level. 1 at the cap, so a bar renders full.
  final double progress;

  /// Whether this player is at the maximum level.
  final bool isMaxLevel;

  /// The line under a progress bar, e.g. `120 / 400 XP`.
  ///
  /// Formatted here rather than at each call site so the profile and the
  /// result screen cannot disagree about how it reads.
  String get progressLabel =>
      isMaxLevel || xpForNextLevel == null ? '$xp XP' : '$xpIntoLevel / $xpForNextLevel XP';

  @override
  List<Object?> get props => <Object?>[level, title, xp, xpIntoLevel, progress, isMaxLevel];

  @override
  bool get stringify => true;
}

/// One achievement, locked or unlocked.
class Achievement extends Equatable {
  /// Creates an achievement.
  const Achievement({
    this.key = '',
    this.name = '',
    this.description = '',
    this.xpReward = 0,
    this.unlocked = false,
    this.unlockedAtMs,
    this.progress = 0,
    this.target = 1,
    this.showProgress = false,
  });

  /// Builds one from a decoded JSON map. Never throws.
  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
        key: asString(json['key']),
        name: asString(json['name']),
        description: asString(json['description']),
        xpReward: asInt(json['xpReward']),
        unlocked: asBool(json['unlocked']),
        unlockedAtMs:
            json['unlockedAtMs'] == null ? null : asInt(json['unlockedAtMs']),
        progress: asInt(json['progress']),
        target: asInt(json['target'], 1),
        showProgress: asBool(json['showProgress']),
      );

  /// The catalogue key. Stable, and what the server stores.
  final String key;

  /// Display name.
  final String name;

  /// What it takes, in one line.
  final String description;

  /// XP paid on unlock.
  final int xpReward;

  /// Whether this player has it.
  final bool unlocked;

  /// When it unlocked, or null while locked.
  final int? unlockedAtMs;

  /// Where the watched counter stands. Never past [target].
  final int progress;

  /// What the counter has to reach.
  final int target;

  /// Whether a progress bar says anything useful for this one.
  final bool showProgress;

  /// Whether this refers to a real catalogue entry.
  bool get isEmpty => key.isEmpty;

  /// 0..1 towards the target.
  double get fraction =>
      target <= 0 ? 0 : (progress / target).clamp(0, 1).toDouble();

  /// The counter line on a card, e.g. `43 / 100`.
  String get progressLabel => '$progress / $target';

  @override
  List<Object?> get props =>
      <Object?>[key, unlocked, unlockedAtMs, progress, target];

  @override
  bool get stringify => true;
}

/// The whole catalogue for one player, with the summary line above it.
class AchievementsPage extends Equatable {
  /// Creates a page.
  const AchievementsPage({
    this.items = const <Achievement>[],
    this.unlockedCount = 0,
    this.totalCount = 0,
  });

  /// Builds a page from a decoded JSON map. Never throws.
  factory AchievementsPage.fromJson(Map<String, dynamic> json) => AchievementsPage(
        items: <Achievement>[
          for (final dynamic raw in asList(json['items']))
            Achievement.fromJson(asMap(raw)),
        ]
            .where((Achievement entry) => !entry.isEmpty)
            .toList(growable: false),
        unlockedCount: asInt(json['unlockedCount']),
        totalCount: asInt(json['totalCount']),
      );

  /// Every catalogue entry, locked and unlocked together.
  final List<Achievement> items;

  /// How many are unlocked.
  final int unlockedCount;

  /// How many there are in total.
  final int totalCount;

  /// An empty catalogue.
  static const AchievementsPage empty = AchievementsPage();

  /// Only the unlocked ones, newest first — the trophy case on a profile.
  List<Achievement> get unlocked =>
      items.where((Achievement entry) => entry.unlocked).toList(growable: false);

  @override
  List<Object?> get props => <Object?>[items, unlockedCount, totalCount];

  @override
  bool get stringify => true;
}

/// Level and achievements together, as the progression screen reads them.
class Progression extends Equatable {
  /// Creates a progression snapshot.
  const Progression({
    this.level = const PlayerLevel(),
    this.achievements = AchievementsPage.empty,
  });

  /// Builds one from a decoded JSON map. Never throws.
  factory Progression.fromJson(Map<String, dynamic> json) => Progression(
        level: PlayerLevel.fromJson(asMap(json['level'])),
        achievements: AchievementsPage.fromJson(asMap(json['achievements'])),
      );

  /// Where the player is on the curve.
  final PlayerLevel level;

  /// The catalogue.
  final AchievementsPage achievements;

  @override
  List<Object?> get props => <Object?>[level, achievements];

  @override
  bool get stringify => true;
}

/// One row of the XP history.
class XpEvent extends Equatable {
  /// Creates a row.
  const XpEvent({
    this.id = '',
    this.reason = '',
    this.amount = 0,
    this.count = 1,
    this.balanceAfter = 0,
    this.atMs = 0,
  });

  /// Builds a row from a decoded JSON map. Never throws.
  factory XpEvent.fromJson(Map<String, dynamic> json) => XpEvent(
        id: asString(json['id']),
        reason: asString(json['reason']),
        amount: asInt(json['amount']),
        count: asInt(json['count'], 1),
        balanceAfter: asInt(json['balanceAfter']),
        atMs: asInt(json['atMs']),
      );

  /// The server-issued row id.
  final String id;

  /// Why it was paid, e.g. `correctGuess` or `achievement:first_win`.
  final String reason;

  /// How much.
  final int amount;

  /// How many times the award applied.
  final int count;

  /// The balance after this award.
  final int balanceAfter;

  /// When, in server milliseconds.
  final int atMs;

  /// Whether this refers to a real row.
  bool get isEmpty => id.isEmpty;

  /// Whether this row came from an achievement rather than from play.
  bool get isAchievement => reason.startsWith('achievement:');

  @override
  List<Object?> get props => <Object?>[id, reason, amount, count, atMs];

  @override
  bool get stringify => true;
}

/// What one finished match paid out, for the result screen.
///
/// Arrives on `s:game:end` beside the standings, so the screen can animate
/// what was earned without a request. It is a *report* of writes the server has
/// already made — the client cannot decline it, alter it, or compute it.
class MatchProgression extends Equatable {
  /// Creates a match report.
  const MatchProgression({
    this.playerId = '',
    this.xpEarned = 0,
    this.level = const PlayerLevel(),
    this.leveledUp = false,
    this.unlocked = const <Achievement>[],
  });

  /// Builds a report from a decoded JSON map. Never throws.
  factory MatchProgression.fromJson(Map<String, dynamic> json) => MatchProgression(
        playerId: asString(json['playerId']),
        xpEarned: asInt(json['xpEarned']),
        level: PlayerLevel.fromJson(asMap(json['level'])),
        leveledUp: asBool(json['leveledUp']),
        unlocked: <Achievement>[
          for (final dynamic raw in asList(json['unlocked']))
            Achievement.fromJson(asMap(raw)),
        ]
            .where((Achievement entry) => !entry.isEmpty)
            .toList(growable: false),
      );

  /// Who this report is for. Always the recipient — reports are per viewer.
  final String playerId;

  /// XP earned this match, including any achievement rewards.
  final int xpEarned;

  /// Where the player stands now.
  final PlayerLevel level;

  /// Whether this match crossed a level boundary.
  final bool leveledUp;

  /// Achievements this match unlocked.
  final List<Achievement> unlocked;

  /// Whether there is anything worth showing.
  bool get isEmpty => xpEarned <= 0 && unlocked.isEmpty;

  @override
  List<Object?> get props =>
      <Object?>[playerId, xpEarned, level, leveledUp, unlocked];

  @override
  bool get stringify => true;
}
