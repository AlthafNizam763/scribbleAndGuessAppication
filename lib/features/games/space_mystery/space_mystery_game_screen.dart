import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/features/games/common/game_audio.dart';
import 'package:scribble_guess/features/games/common/game_chat_overlay.dart';
import 'package:scribble_guess/features/games/common/game_hud.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/game_voice_bar.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/space_mystery/space_mystery_result_overlay.dart';
import 'package:scribble_guess/features/games/space_mystery/widgets/role_reveal.dart';
import 'package:scribble_guess/features/games/space_mystery/widgets/ship_view.dart';
import 'package:scribble_guess/features/games/space_mystery/widgets/space_controls.dart';
import 'package:scribble_guess/features/games/space_mystery/widgets/space_meeting.dart';
import 'package:scribble_guess/features/games/space_mystery/widgets/space_task_panel.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/games/space_mystery_state.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';
import 'package:scribble_guess/providers/games/space_mystery_controller.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Space Mystery, played.
///
/// ## The layout the brief asks for
///
/// Repairs top-left, the ship filling the screen, controls bottom-left, and
/// whatever the player can legally do right now bottom-right. That is a
/// two-thumbs layout and it only works in landscape, which is why the scaffold
/// locks it.
///
/// ## What the client is
///
/// A renderer and an input device, and nothing else. It receives ten frames a
/// second, each one *this player's own view* — the crewmates their line of
/// sight reaches, their own role, their own tasks — and it draws them. It
/// sends a direction when a thumb moves and an intent when a button is
/// pressed. It never decides where anybody is, whether a kill lands, when a
/// task finishes, or who won.
///
/// That is what makes the deduction honest: there is no hidden state in this
/// process to reveal. A player behind a wall was never sent, so a modified
/// client has nothing to draw.
class SpaceMysteryGameScreen extends ConsumerStatefulWidget {
  const SpaceMysteryGameScreen({super.key});

  @override
  ConsumerState<SpaceMysteryGameScreen> createState() =>
      _SpaceMysteryGameScreenState();
}

class _SpaceMysteryGameScreenState
    extends ConsumerState<SpaceMysteryGameScreen> {
  bool _chatOpen = false;

  /// Whether the role card has been dismissed. Shown once, at the start.
  bool _roleSeen = false;

  /// The last event batch we reacted to, so one alarm is one sound.
  int _lastEventMs = 0;

  /// Whether the countdown has already sounded for the sabotage now running.
  ///
  /// Cleared when the sabotage clears, so the next one gets its own warning.
  /// Without this the 10 Hz projection would fire it on every frame of the
  /// last ten seconds — a hundred of them.
  bool _counted = false;

  void _onEvents(SpaceMysteryState state) {
    for (final SpaceEvent event in state.events) {
      if (event.atMs <= _lastEventMs) continue;
      _lastEventMs = event.atMs;

      // The ship's own voice, one sound per thing that happened.
      switch (event.type) {
        case 'task_done':
          _audio.taskDone();
        case 'meeting':
          _audio.meeting();
        case 'sabotage':
          _audio.sabotage();
        case 'eliminated':
        case 'ejected':
          _audio.eliminated();
        case 'vote_cast':
          _audio.voted();
      }
    }
  }

  /// The reactor's last ten seconds, once.
  void _onSabotage(SpaceMysteryState state) {
    final SpaceSabotage? sabotage = state.sabotage;
    if (sabotage == null) {
      _counted = false;
      return;
    }
    if (_counted || sabotage.remainingMs > 10_000) return;
    _counted = true;
    _audio.countdown();
  }

  GameAudio get _audio => ref.read(gameAudioProvider(GameId.spaceMystery));

  @override
  void initState() {
    super.initState();
    unawaited(_audio.warmUp().then((_) {
      if (mounted) _audio.arrive();
    }));
  }

  Future<void> _leave() async {
    final bool go = await confirm(
      context,
      title: 'Abandon the crew?',
      message: 'You leave the ship and the match carries on without you.',
      confirmLabel: 'Abandon',
      destructive: true,
    );
    if (!go || !mounted) return;

    await ref.read(platformSessionProvider.notifier).leave();
    if (!mounted) return;
    context.goNamed(AppRoutes.home);
  }

  Future<void> _sabotage() async {
    final SabotageKind? kind = await showModalBottomSheet<SabotageKind>(
      context: context,
      backgroundColor: GameSkin.spaceMystery.surface,
      builder: (BuildContext sheetContext) => _SabotageSheet(
        onPick: (SabotageKind picked) => Navigator.of(sheetContext).pop(picked),
      ),
    );
    if (kind == null || !mounted) return;
    await ref.read(spaceMysteryControllerProvider).sabotage(kind);
  }

  @override
  Widget build(BuildContext context) {
    final PlatformSession session = ref.watch(platformSessionProvider);
    final SpaceMysteryState state = ref.watch(spaceMysteryStateProvider);
    final ShipMap map = ref.watch(shipMapProvider);
    final String selfId = ref.watch(platformSelfIdProvider);
    final SpaceMysteryController control =
        ref.read(spaceMysteryControllerProvider);

    _onEvents(state);
    _onSabotage(state);

    final SpaceSelf self = state.self;
    final bool frozen = state.inMeeting || !self.alive || self.isWorking;

    return LandscapeGameScaffold(
      skin: GameSkin.spaceMystery,
      connection: session.connection,
      onLeave: _leave,
      table: ShipView(map: map, state: state, selfId: selfId),
      hud: _Hud(
        state: state,
        session: session,
        map: map,
        chatOpen: _chatOpen,
        onToggleChat: () => setState(() => _chatOpen = !_chatOpen),
        frozen: frozen,
        onMove: control.move,
        onRelease: control.halt,
        onUse: control.useStation,
        onReport: control.report,
        onEliminate: control.eliminate,
        onMeeting: control.callMeeting,
        onSabotage: _sabotage,
        onVent: control.vent,
      ),
      overlay: Stack(
        children: <Widget>[
          const GameErrorFlash(),

          // The console panel, while a task is running. Above the ship,
          // because that is the point: a player doing a task is not watching
          // the corridor, and a traitor knows it.
          if (self.isWorking)
            if (map.stationOf(self.workingStationId) case final ShipStation station)
              SpaceTaskPanel(
                station: station,
                remainingMs: self.workingRemainingMs,
                totalMs: station.durationMs,
              ),

          if (state.meeting case final SpaceMeeting meeting)
            SpaceMeetingOverlay(
              state: state,
              meeting: meeting,
              room: session.room,
              selfId: selfId,
              onVote: control.vote,
            ),

          GameChatOverlay(
            open: _chatOpen,
            onClose: () => setState(() => _chatOpen = false),
          ),

          // The role card, once, before anything else can be pressed.
          if (!_roleSeen && state.isPlaying && self.playerId.isNotEmpty)
            RoleReveal(
              self: self,
              room: session.room,
              onDismissed: () => setState(() => _roleSeen = true),
            ),

          if (state.isOver)
            SpaceMysteryResultOverlay(
              state: state,
              room: session.room,
              selfId: selfId,
            ),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.state,
    required this.session,
    required this.map,
    required this.chatOpen,
    required this.onToggleChat,
    required this.frozen,
    required this.onMove,
    required this.onRelease,
    required this.onUse,
    required this.onReport,
    required this.onEliminate,
    required this.onMeeting,
    required this.onSabotage,
    required this.onVent,
  });

  final SpaceMysteryState state;
  final PlatformSession session;
  final ShipMap map;
  final bool chatOpen;
  final VoidCallback onToggleChat;
  final bool frozen;
  final void Function(double, double) onMove;
  final VoidCallback onRelease;
  final ValueChanged<String> onUse;
  final VoidCallback onReport;
  final ValueChanged<String> onEliminate;
  final VoidCallback onMeeting;
  final VoidCallback onSabotage;
  final VoidCallback onVent;

  @override
  Widget build(BuildContext context) {
    final GameMetrics metrics = context.metrics;
    final SpaceSelf self = state.self;

    return Stack(
      children: <Widget>[
        GameHudBar(
          title: 'Space Mystery',
          headline: state.sabotage == null
              ? GameHeadline(
                  label: !self.alive
                      ? 'You are dead — watching'
                      : self.isTraitor
                          ? 'Traitor'
                          : 'Crew',
                  detail: self.alive
                      ? '${self.tasksDone}/${self.tasks.length} tasks'
                      : null,
                  mine: self.isTraitor,
                )
              : SabotageBanner(sabotage: state.sabotage!),
          actions: <Widget>[
            // One bar for all three games, in each one's own colours.
            const GameVoiceBar(),
            GameIconButton(
              icon: Icons.chat_bubble_outline_rounded,
              tooltip: 'Crew chat',
              active: chatOpen,
              badge: chatOpen ? 0 : session.chat.length,
              onPressed: onToggleChat,
            ),
          ],
        ),

        // Repairs, top-left, under the bar.
        Positioned(
          left: metrics.gutter,
          top: 48 * metrics.scale,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TaskProgressBar(state: state),
              if (self.alive && !state.inMeeting) ...<Widget>[
                SizedBox(height: metrics.gutter * 0.4),
                TaskCompass(state: state, map: map),
              ],
            ],
          ),
        ),

        // Movement, bottom-left.
        if (!frozen)
          Positioned(
            left: metrics.gutter * 0.4,
            bottom: metrics.gutter * 0.4,
            child: SpaceJoystick(
              enabled: true,
              onMove: onMove,
              onRelease: onRelease,
            ),
          ),

        // What can be done, bottom-right.
        if (!state.inMeeting)
          Positioned(
            right: metrics.gutter,
            bottom: metrics.gutter * 0.4,
            child: SpaceActions(
              state: state,
              map: map,
              onUse: onUse,
              onReport: onReport,
              onEliminate: onEliminate,
              onMeeting: onMeeting,
              onSabotage: onSabotage,
              onVent: onVent,
            ),
          ),
      ],
    );
  }
}

/// The three things a traitor can pull.
class _SabotageSheet extends StatelessWidget {
  const _SabotageSheet({required this.onPick});

  final ValueChanged<SabotageKind> onPick;

  @override
  Widget build(BuildContext context) {
    const GameSkin skin = GameSkin.spaceMystery;
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'SABOTAGE',
              style: text.labelMedium?.copyWith(
                color: skin.inkMuted,
                fontFamily: skin.display,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final SabotageKind kind in SabotageKind.values)
              ListTile(
                onTap: () => onPick(kind),
                leading: Icon(
                  switch (kind) {
                    SabotageKind.breach => Icons.local_fire_department_rounded,
                    SabotageKind.lights => Icons.lightbulb_outline_rounded,
                    SabotageKind.comms => Icons.wifi_off_rounded,
                  },
                  color: skin.danger,
                ),
                title: Text(
                  kind.title,
                  style: text.bodyLarge?.copyWith(
                    color: skin.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  kind.detail,
                  style: text.bodySmall?.copyWith(color: skin.inkMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
