import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/common/bot_chip.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/models/games/space_mystery_state.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The meeting: everybody round the table, then the vote.
///
/// ## Two phases, one screen
///
/// Discussion and voting are the same room with different controls, so they
/// are the same widget with the seats becoming selectable. Pushing a separate
/// voting screen would throw away the discussion above it at exactly the
/// moment somebody is deciding what to do about it.
///
/// ## What is deliberately withheld
///
/// Who has voted is shown. **What they voted is not**, until the server counts
/// it — that is the whole tension of the last ten seconds, and the server does
/// not send it either, so there is nothing here to leak. A player who has
/// voted sees their own choice and nobody else's.
class SpaceMeetingOverlay extends StatelessWidget {
  const SpaceMeetingOverlay({
    required this.state,
    required this.meeting,
    required this.room,
    required this.selfId,
    required this.onVote,
    super.key,
  });

  final SpaceMysteryState state;
  final SpaceMeeting meeting;
  final PlatformRoom? room;
  final String selfId;

  /// `null` is a deliberate skip, which is a real vote and not an abstention.
  final ValueChanged<String?> onVote;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final int seconds = (meeting.remainingMs / 1000).ceil();
    final bool canVote = meeting.isVoting && state.self.alive && !meeting.hasVoted;

    final List<SpaceCrewmate> living = <SpaceCrewmate>[
      for (final SpaceCrewmate mate in state.visible) if (mate.alive) mate,
    ];
    final List<SpaceCrewmate> dead = <SpaceCrewmate>[
      for (final SpaceCrewmate mate in state.visible) if (!mate.alive) mate,
    ];

    return Positioned.fill(
      child: ColoredBox(
        color: skin.backdrop.last.withValues(alpha: 0.95),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(metrics.gutter),
            child: Column(
              children: <Widget>[
                _Header(
                  meeting: meeting,
                  room: room,
                  selfId: selfId,
                  seconds: seconds,
                ),
                SizedBox(height: metrics.gutter * 0.6),

                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // The table, taking most of the width: this is a room
                      // full of people looking at each other.
                      Expanded(
                        flex: 3,
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: metrics.gutter * 0.6,
                            runSpacing: metrics.gutter * 0.6,
                            alignment: WrapAlignment.center,
                            children: <Widget>[
                              for (final SpaceCrewmate mate in living)
                                _MeetingSeat(
                                  mate: mate,
                                  player: room?.seatOf(mate.playerId),
                                  crewKind: state.crewKindOf(mate.playerId),
                                  hasVoted: meeting.voted.contains(mate.playerId),
                                  isSelf: mate.playerId == selfId,
                                  isMyVote: meeting.yourVote == mate.playerId,
                                  selectable: canVote && mate.playerId != selfId,
                                  onTap: () => onVote(mate.playerId),
                                ),
                              for (final SpaceCrewmate mate in dead)
                                _MeetingSeat(
                                  mate: mate,
                                  player: room?.seatOf(mate.playerId),
                                  crewKind: state.crewKindOf(mate.playerId),
                                  hasVoted: false,
                                  isSelf: mate.playerId == selfId,
                                  isMyVote: false,
                                  selectable: false,
                                  onTap: () {},
                                ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(width: metrics.gutter),

                      // What has been said. Bots speak here from what they
                      // actually saw, so an accusation is evidence of a kind.
                      Expanded(
                        flex: 2,
                        child: _Transcript(
                          meeting: meeting,
                          room: room,
                          selfId: selfId,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: metrics.gutter * 0.5),
                _Footer(
                  meeting: meeting,
                  state: state,
                  canVote: canVote,
                  onSkip: () => onVote(null),
                  text: text,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.meeting,
    required this.room,
    required this.selfId,
    required this.seconds,
  });

  final SpaceMeeting meeting;
  final PlatformRoom? room;
  final String selfId;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final String caller = _name(meeting.callerId, room, selfId);
    final String headline = meeting.calledForBody
        ? '${_name(meeting.bodyOf, room, selfId)} was found'
        : '$caller called an emergency meeting';

    return Row(
      children: <Widget>[
        Icon(
          meeting.calledForBody
              ? Icons.report_gmailerrorred_rounded
              : Icons.notifications_active_rounded,
          color: skin.danger,
          size: 24 * metrics.scale,
        ),
        SizedBox(width: metrics.gutter * 0.5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                headline,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(
                  color: skin.ink,
                  fontFamily: skin.display,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                meeting.isVoting ? 'Vote now' : 'Discuss',
                style: text.labelMedium?.copyWith(color: skin.inkMuted),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.gutter * 0.8,
            vertical: metrics.gutter * 0.35,
          ),
          decoration: BoxDecoration(
            color: seconds <= 5 ? skin.danger : skin.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(color: seconds <= 5 ? skin.danger : skin.edge),
          ),
          child: Text(
            '${seconds}s',
            style: text.titleMedium?.copyWith(
              color: skin.ink,
              fontFamily: skin.display,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _MeetingSeat extends StatelessWidget {
  const _MeetingSeat({
    required this.mate,
    required this.player,
    required this.crewKind,
    required this.hasVoted,
    required this.isSelf,
    required this.isMyVote,
    required this.selectable,
    required this.onTap,
  });

  final SpaceCrewmate mate;
  final PlatformSeat? player;

  /// Which of the Space Crew this seat is. Cosmetic, and the thing that makes
  /// "the medic was in Hydroponics" a sentence somebody can check.
  final SpaceCrewKind crewKind;

  final bool hasVoted;
  final bool isSelf;
  final bool isMyVote;
  final bool selectable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      button: selectable,
      label: '${mate.username}, ${crewKind.title}${mate.alive ? '' : ', dead'}',
      child: GestureDetector(
        onTap: selectable ? onTap : null,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          width: 118 * metrics.scale,
          padding: EdgeInsets.symmetric(
            horizontal: metrics.gutter * 0.5,
            vertical: metrics.gutter * 0.45,
          ),
          decoration: BoxDecoration(
            color: mate.alive
                ? skin.surface
                : skin.surface.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: isMyVote
                  ? skin.danger
                  : selectable
                      ? skin.accent.withValues(alpha: 0.55)
                      : skin.edge,
              width: isMyVote ? 2 : AppSpacing.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  if (player != null)
                    PlayerAvatar(
                      avatarId: player!.avatarId,
                      colorIndex: player!.avatarColorIndex,
                      size: 34 * metrics.scale,
                      dimmed: !mate.alive,
                    )
                  else
                    Icon(Icons.person, color: skin.inkMuted, size: 34 * metrics.scale),
                  if (hasVoted)
                    Positioned(
                      right: -4,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: skin.success,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.how_to_vote_rounded,
                          size: 10 * metrics.scale,
                          color: skin.backdrop.last,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: metrics.gutter * 0.3),
              Text(
                isSelf ? 'You' : mate.username,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium?.copyWith(
                  color: mate.alive ? skin.ink : skin.inkMuted,
                  fontWeight: FontWeight.w700,
                  decoration: mate.alive ? null : TextDecoration.lineThrough,
                ),
              ),
              Text(
                crewKind.title.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(
                  color: skin.inkMuted,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (player?.isBot ?? false) ...<Widget>[
                SizedBox(height: metrics.gutter * 0.2),
                BotChip(difficulty: player!.botDifficulty),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.meeting,
    required this.room,
    required this.selfId,
  });

  final SpaceMeeting meeting;
  final PlatformRoom? room;
  final String selfId;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.all(metrics.gutter * 0.6),
      decoration: BoxDecoration(
        color: skin.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: skin.edge),
      ),
      child: meeting.said.isEmpty
          ? Center(
              child: Text(
                'Nobody has said anything.',
                style: text.bodySmall?.copyWith(color: skin.inkMuted),
              ),
            )
          : ListView.builder(
              itemCount: meeting.said.length,
              itemBuilder: (BuildContext context, int index) {
                final SpaceRemark remark = meeting.said[index];
                return Padding(
                  padding: EdgeInsets.only(bottom: metrics.gutter * 0.4),
                  child: RichText(
                    text: TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: '${_name(remark.playerId, room, selfId)}: ',
                          style: text.labelSmall?.copyWith(
                            color: skin.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text: remark.text,
                          style: text.bodySmall?.copyWith(color: skin.ink),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.meeting,
    required this.state,
    required this.canVote,
    required this.onSkip,
    required this.text,
  });

  final SpaceMeeting meeting;
  final SpaceMysteryState state;
  final bool canVote;
  final VoidCallback onSkip;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;

    if (!state.self.alive) {
      return Text(
        'You are dead. You can watch, and that is all.',
        style: text.bodySmall?.copyWith(color: skin.inkMuted),
      );
    }

    if (meeting.isDiscussion) {
      return Text(
        'Voting opens when the discussion ends.',
        style: text.bodySmall?.copyWith(color: skin.inkMuted),
      );
    }

    if (meeting.hasVoted) {
      // The state every player spends the last twenty seconds in. It has to be
      // clear that the vote landed and that nothing more is expected.
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 14 * metrics.scale,
            height: 14 * metrics.scale,
            child: CircularProgressIndicator(strokeWidth: 2, color: skin.accent),
          ),
          SizedBox(width: metrics.gutter * 0.5),
          Text(
            meeting.yourVote.isEmpty
                ? 'You skipped. Waiting for the others…'
                : 'Vote cast. Waiting for the others…',
            style: text.labelLarge?.copyWith(color: skin.inkMuted),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          'Tap somebody to vote them out',
          style: text.labelLarge?.copyWith(color: skin.ink),
        ),
        SizedBox(width: metrics.gutter),
        OutlinedButton(
          onPressed: canVote ? onSkip : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: skin.inkMuted,
            side: BorderSide(color: skin.edge),
          ),
          child: const Text('Skip'),
        ),
      ],
    );
  }
}

String _name(String playerId, PlatformRoom? room, String selfId) {
  if (playerId.isEmpty) return 'Somebody';
  if (playerId == selfId) return 'You';
  return room?.seatOf(playerId)?.username ?? 'Somebody';
}
