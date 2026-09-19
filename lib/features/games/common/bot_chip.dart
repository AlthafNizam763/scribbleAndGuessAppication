import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The small flag that marks a seat as a Stupid rather than a person.
///
/// ## Why it is small, and why it is always there
///
/// The brief for all three games is the same: a bot looks exactly like a
/// player apart from a clear indicator. Both halves matter. If the badge were
/// large, or the seat were styled differently, a table with four bots in it
/// would read as a practice mode rather than as a game — and the whole point
/// of seating them is that a lobby which would otherwise never fill can play a
/// real match. If there were no badge at all, a player could be made to think
/// they had beaten five people.
///
/// It carries the difficulty as well as the fact, because "Chaos Kitty on
/// Easy" and "Chaos Kitty on Hard" are genuinely different opponents — the
/// dial changes what a bot *notices*, not just how often it slips — and a
/// player deserves to know which one is sitting opposite them.
class BotChip extends StatelessWidget {
  const BotChip({required this.difficulty, this.compact = true, super.key});

  /// `null` renders a bare `BOT`, for a seat whose difficulty is unknown.
  final BotDifficulty? difficulty;

  /// Smaller still, for a crowded seat badge.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: (compact ? 5 : 7) * metrics.scale,
        vertical: (compact ? 1 : 2) * metrics.scale,
      ),
      decoration: BoxDecoration(
        color: skin.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        border: Border.all(color: skin.accent.withValues(alpha: 0.6)),
      ),
      child: Text(
        difficulty == null ? 'BOT' : 'BOT · ${difficulty!.label.toUpperCase()}',
        style: TextStyle(
          color: skin.accent,
          fontSize: (compact ? 8 : 9) * metrics.scale,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          height: 1.4,
        ),
      ),
    );
  }
}
