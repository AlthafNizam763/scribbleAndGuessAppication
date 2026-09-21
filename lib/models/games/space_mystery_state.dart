import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// Which side of the airlock somebody is on.
enum SpaceRole {
  crew('crew'),
  saboteur('saboteur');

  const SpaceRole(this.wire);
  final String wire;

  static SpaceRole? fromWire(String value) {
    for (final SpaceRole role in values) {
      if (role.wire == value) return role;
    }
    return null;
  }
}

/// What the station is doing to the crew right now.
///
/// Five, in two groups. [reactor] and [oxygen] carry a deadline the crew can
/// actually lose to, and both are answered at two consoles held at the same
/// moment. The other three are a cost rather than a threat: they make the work
/// harder and everybody's whereabouts less accountable, which is often the
/// more useful thing for a saboteur to buy.
enum SabotageKind {
  reactor(
    'reactor',
    'Reactor critical',
    'Hold both containment consoles before the core goes.',
  ),
  oxygen(
    'oxygen',
    'Oxygen failure',
    'Purge both scrubbers before the air runs out.',
  ),
  power(
    'power',
    'Power failure',
    'The lights are down. You cannot see far — they can.',
  ),
  comms(
    'comms',
    'Communication jam',
    'Your job list is offline until the channel clears.',
  ),
  engine(
    'engine',
    'Engine lock',
    'The deck plates are dragging. Everyone else is quicker than you.',
  );

  const SabotageKind(this.wire, this.title, this.detail);

  final String wire;
  final String title;
  final String detail;

  static SabotageKind? fromWire(String value) {
    for (final SabotageKind kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// The eight members of the Space Crew, as visual identities.
///
/// ## Cosmetic, and why that is the right call
///
/// These are **not** roles. The server decides who is crew and who is a
/// saboteur and tells each player only what they are entitled to know; nothing
/// here touches that. What this is for is making eight suits on a dark deck
/// tellable apart, and giving a player something to say in a meeting other
/// than a colour — "the medic was in Hydroponics" is a sentence, and it is one
/// everybody at the table can check.
///
/// Derived from the seat order the server already sends, so every client
/// draws the same person in the same suit for the whole match, and a player
/// who looked away still recognises who came back through the door.
///
/// If a future version gives these mechanical weight, the server assigns them
/// and this becomes a projection field. It is deliberately not one yet: a
/// visual identity that is decided on the client cannot leak anything, and one
/// that is decided on the server has to be thought about very carefully.
enum SpaceCrewKind {
  engineer('Engineer'),
  scientist('Scientist'),
  navigator('Navigator'),
  mechanic('Mechanic'),
  medic('Medic'),
  security('Security'),
  researcher('Researcher'),
  technician('Technician');

  const SpaceCrewKind(this.title);

  /// What this crew member is called. Said out loud in meetings.
  final String title;
}

/// Which hands-on job a console sets, and therefore which panel opens at it.
///
/// Fixed per station in the floor plan, so a player learns the station: the
/// Reactor Core is always a bearing to line up. What changes every time is the
/// puzzle, which the server deals fresh on each attempt.
enum SpaceTaskKind {
  align('align'),
  sliders('sliders'),
  sequence('sequence'),
  match('match'),
  rewire('rewire');

  const SpaceTaskKind(this.wire);
  final String wire;

  static SpaceTaskKind? fromWire(String value) {
    for (final SpaceTaskKind kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// A module of ORBITAL-7, as the server described it at match start.
@immutable
class ShipRoom {
  const ShipRoom({required this.id, required this.name, required this.bounds});

  factory ShipRoom.fromJson(Map<String, dynamic> json) => ShipRoom(
        id: asString(json['id']),
        name: asString(json['name']),
        bounds: Rect.fromLTWH(
          asDouble(json['x']),
          asDouble(json['y']),
          asDouble(json['width']),
          asDouble(json['height']),
        ),
      );

  final String id;

  /// What a player calls it in a meeting. "I was in the reactor core."
  final String name;

  final Rect bounds;
}

/// A console somebody has to stand at.
@immutable
class ShipStation {
  const ShipStation({
    required this.id,
    required this.roomId,
    required this.name,
    required this.kind,
    required this.position,
    required this.durationMs,
  });

  factory ShipStation.fromJson(Map<String, dynamic> json) => ShipStation(
        id: asString(json['id']),
        roomId: asString(json['roomId']),
        name: asString(json['name']),
        kind: SpaceTaskKind.fromWire(asString(json['kind'])) ?? SpaceTaskKind.align,
        position: Offset(asDouble(json['x']), asDouble(json['y'])),
        durationMs: asInt(json['durationMs']),
      );

  final String id;
  final String roomId;
  final String name;

  /// Which job this console sets. The same one every time, on purpose.
  final SpaceTaskKind kind;

  final Offset position;

  /// The shortest the server will make somebody stand here. A floor, not a
  /// clock: the job finishes on a right answer, never on this elapsing.
  final int durationMs;
}

/// A console the crew answers a sabotage at.
@immutable
class ShipRepair {
  const ShipRepair({
    required this.id,
    required this.roomId,
    required this.position,
  });

  factory ShipRepair.fromJson(Map<String, dynamic> json) => ShipRepair(
        id: asString(json['id']),
        roomId: asString(json['roomId']),
        position: Offset(asDouble(json['x']), asDouble(json['y'])),
      );

  final String id;
  final String roomId;
  final Offset position;
}

/// A vent mouth. Only ever drawn for a player entitled to use one.
@immutable
class ShipVent {
  const ShipVent({required this.id, required this.position, required this.network});

  factory ShipVent.fromJson(Map<String, dynamic> json) => ShipVent(
        id: asString(json['id']),
        position: Offset(asDouble(json['x']), asDouble(json['y'])),
        network: asString(json['network']),
      );

  final String id;
  final Offset position;

  /// Vents connect only to other mouths carrying the same network.
  final String network;
}

/// The floor plan, handed over once when a match starts.
///
/// ## Why the client is given the map at all
///
/// To draw it. Movement is decided entirely on the server — a client sends a
/// direction and is told where that put it — so this copy is scenery. A client
/// that deleted a wall from its own would simply walk into one it could not
/// see, which is the point: the walls are not enforced here, they are enforced
/// where the positions are computed.
@immutable
class ShipMap {
  const ShipMap({
    required this.name,
    required this.world,
    required this.rooms,
    required this.corridors,
    required this.stations,
    required this.vents,
    required this.repairStations,
    required this.sabotageStations,
    required this.meetingTable,
    required this.playerRadius,
  });

  static const ShipMap empty = ShipMap(
    name: 'ORBITAL-7',
    world: Rect.fromLTWH(0, 0, 100, 60),
    rooms: <ShipRoom>[],
    corridors: <Rect>[],
    stations: <ShipStation>[],
    vents: <ShipVent>[],
    repairStations: <ShipRepair>[],
    sabotageStations: <String, List<ShipRepair>>{},
    meetingTable: Offset(52, 31),
    playerRadius: 1.2,
  );

  factory ShipMap.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> world = asMap(json['world']);

    return ShipMap(
      name: asString(json['shipName'], 'ORBITAL-7'),
      world: Rect.fromLTWH(
        0,
        0,
        asDouble(world['width'], 100),
        asDouble(world['height'], 60),
      ),
      rooms: <ShipRoom>[
        for (final Object? row in asList(json['rooms']))
          if (row is Map) ShipRoom.fromJson(asMap(row)),
      ],
      corridors: <Rect>[
        for (final Object? row in asList(json['corridors']))
          if (row is Map)
            Rect.fromLTWH(
              asDouble(asMap(row)['x']),
              asDouble(asMap(row)['y']),
              asDouble(asMap(row)['width']),
              asDouble(asMap(row)['height']),
            ),
      ],
      stations: <ShipStation>[
        for (final Object? row in asList(json['stations']))
          if (row is Map) ShipStation.fromJson(asMap(row)),
      ],
      vents: <ShipVent>[
        for (final Object? row in asList(json['vents']))
          if (row is Map) ShipVent.fromJson(asMap(row)),
      ],
      repairStations: <ShipRepair>[
        for (final Object? row in asList(json['repairStations']))
          if (row is Map) ShipRepair.fromJson(asMap(row)),
      ],
      sabotageStations: <String, List<ShipRepair>>{
        for (final MapEntry<String, dynamic> entry
            in asMap(json['sabotageStations']).entries)
          entry.key: <ShipRepair>[
            for (final Object? row in asList(entry.value))
              if (row is Map) ShipRepair.fromJson(asMap(row)),
          ],
      },
      meetingTable: Offset(
        asDouble(asMap(json['meetingTable'])['x'], 52),
        asDouble(asMap(json['meetingTable'])['y'], 31),
      ),
      playerRadius: asDouble(json['playerRadius'], 1.2),
    );
  }

  /// What the station is called. Drawn on the HUD, said in the role card.
  final String name;

  final Rect world;
  final List<ShipRoom> rooms;
  final List<Rect> corridors;
  final List<ShipStation> stations;
  final List<ShipVent> vents;

  /// Every console on the station a sabotage is answered at.
  final List<ShipRepair> repairStations;

  /// Which of those answer which sabotage, keyed by its wire name.
  final Map<String, List<ShipRepair>> sabotageStations;

  final Offset meetingTable;
  final double playerRadius;

  /// The consoles that clear [kind], or none for one that can only be waited
  /// out.
  List<ShipRepair> repairsFor(SabotageKind kind) =>
      sabotageStations[kind.wire] ?? const <ShipRepair>[];

  bool get isEmpty => rooms.isEmpty;

  ShipStation? stationOf(String id) {
    for (final ShipStation station in stations) {
      if (station.id == id) return station;
    }
    return null;
  }

  /// The room a point is in, or `null` in a corridor.
  ShipRoom? roomAt(Offset point) {
    for (final ShipRoom room in rooms) {
      if (room.bounds.contains(point)) return room;
    }
    return null;
  }
}

/// Somebody the local player can currently see.
///
/// ## What is not here
///
/// Everybody they cannot see. The server sends only the crewmates inside this
/// viewer's line of sight — a player behind a wall is not in the payload at
/// all — so this list is short on purpose, and a client that wanted to draw
/// through walls has nothing to draw with.
@immutable
class SpaceCrewmate {
  const SpaceCrewmate({
    required this.playerId,
    required this.username,
    required this.isBot,
    required this.position,
    required this.facing,
    required this.alive,
    required this.venting,
    required this.working,
    required this.role,
  });

  factory SpaceCrewmate.fromJson(Map<String, dynamic> json) => SpaceCrewmate(
        playerId: asString(json['playerId']),
        username: asString(json['username']),
        isBot: asBool(json['isBot']),
        position: Offset(asDouble(json['x']), asDouble(json['y'])),
        facing: asInt(json['facing'], 1),
        alive: asBool(json['alive'], true),
        venting: asBool(json['venting']),
        working: asBool(json['working']),
        // Null for everybody the viewer is not entitled to know about, which
        // is almost always everybody.
        role: SpaceRole.fromWire(asString(json['role'])),
      );

  final String playerId;
  final String username;
  final bool isBot;
  final Offset position;

  /// -1 or 1. Which way the little body is looking.
  final int facing;

  final bool alive;
  final bool venting;

  /// Standing at a console. Visible to everybody, which is what lets a saboteur
  /// fake a task and be seen doing it.
  final bool working;

  /// `null` unless the viewer is entitled to it: their own, their fellow
  /// saboteurs', or everybody's once the match is over.
  final SpaceRole? role;
}

/// A body on the floor.
@immutable
class SpaceBody {
  const SpaceBody({required this.playerId, required this.position});

  factory SpaceBody.fromJson(Map<String, dynamic> json) => SpaceBody(
        playerId: asString(json['playerId']),
        position: Offset(asDouble(json['x']), asDouble(json['y'])),
      );

  final String playerId;
  final Offset position;
}

/// One of this player's own tasks.
@immutable
class SpaceTask {
  const SpaceTask({required this.stationId, required this.done});

  factory SpaceTask.fromJson(Map<String, dynamic> json) => SpaceTask(
        stationId: asString(json['stationId']),
        done: asBool(json['done']),
      );

  final String stationId;
  final bool done;
}

/// The job open in front of the local player, and the puzzle it set.
///
/// ## Why the puzzle arrives from the server
///
/// Because the server is the thing that will judge the answer. It deals the
/// job when the console is opened, sends [spec] — and only [spec] — and then
/// re-derives what a right answer looks like from the same data when one comes
/// back. Nothing in this class can finish a task, and there is no answer key
/// in it to find: a panel that ran the check locally would be a panel a
/// modified client could simply skip.
@immutable
class SpaceWork {
  const SpaceWork({
    required this.stationId,
    required this.kind,
    required this.spec,
    required this.readyInMs,
    required this.expiresInMs,
  });

  static SpaceWork? fromJson(Map<String, dynamic> json) {
    final String stationId = asString(json['stationId']);
    if (stationId.isEmpty) return null;

    return SpaceWork(
      stationId: stationId,
      kind: SpaceTaskKind.fromWire(asString(json['kind'])) ?? SpaceTaskKind.align,
      spec: asMap(json['spec']),
      readyInMs: asInt(json['readyInMs']),
      expiresInMs: asInt(json['expiresInMs']),
    );
  }

  final String stationId;
  final SpaceTaskKind kind;

  /// The puzzle, as the server generated it. Read by the panel, never solved
  /// by it — the answer goes back over the wire to be judged.
  final Map<String, dynamic> spec;

  /// What is left of the station's time floor. The ACCEPT control stays
  /// disabled until this reaches zero, and the server refuses an early answer
  /// anyway.
  final int readyInMs;

  final int expiresInMs;

  bool get ready => readyInMs <= 0;
}

/// The local player's own card. The only place a role is ever named.
@immutable
class SpaceSelf {
  const SpaceSelf({
    required this.playerId,
    required this.role,
    required this.alive,
    required this.position,
    required this.tasks,
    required this.work,
    required this.killCooldownMs,
    required this.ventId,
    required this.emergenciesLeft,
    required this.allies,
  });

  static const SpaceSelf unknown = SpaceSelf(
    playerId: '',
    role: SpaceRole.crew,
    alive: true,
    position: Offset.zero,
    tasks: <SpaceTask>[],
    work: null,
    killCooldownMs: 0,
    ventId: null,
    emergenciesLeft: 0,
    allies: <String>[],
  );

  factory SpaceSelf.fromJson(Map<String, dynamic> json) {
    return SpaceSelf(
      playerId: asString(json['playerId']),
      role: SpaceRole.fromWire(asString(json['role'])) ?? SpaceRole.crew,
      alive: asBool(json['alive'], true),
      position: Offset(asDouble(json['x']), asDouble(json['y'])),
      tasks: <SpaceTask>[
        for (final Object? row in asList(json['tasks']))
          if (row is Map) SpaceTask.fromJson(asMap(row)),
      ],
      work: SpaceWork.fromJson(asMap(json['working'])),
      killCooldownMs: asInt(json['killCooldownMs']),
      ventId: asString(json['ventId']).isEmpty ? null : asString(json['ventId']),
      emergenciesLeft: asInt(json['emergenciesLeft']),
      allies: asStringList(json['allies']),
    );
  }

  final String playerId;
  final SpaceRole role;
  final bool alive;
  final Offset position;
  final List<SpaceTask> tasks;

  /// The console open in front of them, or null.
  final SpaceWork? work;

  /// Milliseconds until this saboteur may act again. Always 0 for crew.
  final int killCooldownMs;

  final String? ventId;
  final int emergenciesLeft;

  /// Fellow saboteurs. Empty for crew, always.
  final List<String> allies;

  bool get isSaboteur => role == SpaceRole.saboteur;
  bool get isWorking => work != null;

  /// The console being worked at, or empty.
  String get workingStationId => work?.stationId ?? '';

  bool get isVenting => ventId != null;
  bool get canEliminate => isSaboteur && alive && killCooldownMs <= 0;

  int get tasksDone => tasks.where((SpaceTask task) => task.done).length;
}

/// A meeting in progress.
@immutable
class SpaceMeeting {
  const SpaceMeeting({
    required this.reason,
    required this.callerId,
    required this.bodyOf,
    required this.phase,
    required this.remainingMs,
    required this.voted,
    required this.said,
    required this.yourVote,
    required this.hasVoted,
  });

  static SpaceMeeting? fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return null;

    return SpaceMeeting(
      reason: asString(json['reason']),
      callerId: asString(json['callerId']),
      bodyOf: asString(json['bodyOf']),
      phase: asString(json['phase']),
      remainingMs: asInt(json['remainingMs']),
      voted: asStringList(json['voted']),
      said: <SpaceRemark>[
        for (final Object? row in asList(json['said']))
          if (row is Map) SpaceRemark.fromJson(asMap(row)),
      ],
      yourVote: asString(json['yourVote']),
      // A skip is a real vote recorded as null, so "did I vote" cannot be
      // answered by looking at the target.
      hasVoted: json.containsKey('yourVote'),
    );
  }

  final String reason;
  final String callerId;

  /// Whose body started this, or empty for an emergency meeting.
  final String bodyOf;

  /// `discussion` then `voting`.
  final String phase;

  final int remainingMs;

  /// Who has voted. **Never what they voted**, until the count.
  final List<String> voted;

  final List<SpaceRemark> said;

  /// This player's own vote. Empty means they skipped.
  final String yourVote;

  final bool hasVoted;

  bool get isVoting => phase == 'voting';
  bool get isDiscussion => phase == 'discussion';
  bool get calledForBody => bodyOf.isNotEmpty;
}

/// Something somebody said in a meeting.
@immutable
class SpaceRemark {
  const SpaceRemark({
    required this.playerId,
    required this.text,
    required this.atMs,
  });

  factory SpaceRemark.fromJson(Map<String, dynamic> json) => SpaceRemark(
        playerId: asString(json['playerId']),
        text: asString(json['text']),
        atMs: asInt(json['atMs']),
      );

  final String playerId;
  final String text;
  final int atMs;
}

/// A sabotage in progress.
@immutable
class SpaceSabotage {
  const SpaceSabotage({
    required this.kind,
    required this.critical,
    required this.remainingMs,
    required this.holds,
    required this.stations,
  });

  static SpaceSabotage? fromJson(Map<String, dynamic> json) {
    final SabotageKind? kind = SabotageKind.fromWire(asString(json['kind']));
    if (kind == null) return null;

    return SpaceSabotage(
      kind: kind,
      critical: asBool(json['critical']),
      remainingMs: asInt(json['remainingMs']),
      holds: <String, bool>{
        for (final MapEntry<String, dynamic> entry in asMap(json['holds']).entries)
          entry.key: asBool(entry.value),
      },
      stations: <ShipRepair>[
        for (final Object? row in asList(json['stations']))
          if (row is Map) ShipRepair.fromJson(asMap(row)),
      ],
    );
  }

  final SabotageKind kind;

  /// Whether running this one out loses the match. The HUD shouts for these
  /// and merely reports the rest.
  final bool critical;

  final int remainingMs;

  /// Which consoles are currently held down. Never *who* is holding them: the
  /// alarm panel shows the station, not a roster.
  final Map<String, bool> holds;

  /// Where to go and answer it. Empty for a jam, which can only be waited out.
  final List<ShipRepair> stations;

  int get heldCount => holds.values.where((bool held) => held).length;

  /// Whether anybody can do anything about this one at all.
  bool get answerable => stations.isNotEmpty;
}

/// Something public that just happened.
@immutable
class SpaceEvent {
  const SpaceEvent({
    required this.type,
    required this.playerId,
    required this.targetId,
    required this.detail,
    required this.atMs,
  });

  factory SpaceEvent.fromJson(Map<String, dynamic> json) => SpaceEvent(
        type: asString(json['type']),
        playerId: asString(json['playerId']),
        targetId: asString(json['targetId']),
        detail: asString(json['detail']),
        atMs: asInt(json['atMs']),
      );

  final String type;
  final String playerId;
  final String targetId;
  final String detail;
  final int atMs;
}

/// One frame of the ship, ten times a second.
@immutable
class SpaceMysteryState {
  const SpaceMysteryState({
    required this.status,
    required this.phase,
    required this.serverMs,
    required this.self,
    required this.visible,
    required this.seats,
    required this.bodies,
    required this.taskProgress,
    required this.taskDone,
    required this.taskTotal,
    required this.sabotage,
    required this.meeting,
    required this.events,
    required this.result,
  });

  static const SpaceMysteryState empty = SpaceMysteryState(
    status: '',
    phase: 'station',
    serverMs: 0,
    self: SpaceSelf.unknown,
    visible: <SpaceCrewmate>[],
    seats: <String>[],
    bodies: <SpaceBody>[],
    taskProgress: 0,
    taskDone: 0,
    taskTotal: 0,
    sabotage: null,
    meeting: null,
    events: <SpaceEvent>[],
    result: null,
  );

  factory SpaceMysteryState.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> result = asMap(json['result']);

    return SpaceMysteryState(
      status: asString(json['status']),
      phase: asString(json['phase'], 'station'),
      serverMs: asInt(json['serverMs']),
      self: json['you'] == null
          ? SpaceSelf.unknown
          : SpaceSelf.fromJson(asMap(json['you'])),
      visible: <SpaceCrewmate>[
        for (final Object? row in asList(json['players']))
          if (row is Map) SpaceCrewmate.fromJson(asMap(row)),
      ],
      seats: asStringList(json['seats']),
      bodies: <SpaceBody>[
        for (final Object? row in asList(json['bodies']))
          if (row is Map) SpaceBody.fromJson(asMap(row)),
      ],
      taskProgress: asDouble(json['taskProgress']),
      taskDone: asInt(json['taskDone']),
      taskTotal: asInt(json['taskTotal']),
      sabotage: SpaceSabotage.fromJson(asMap(json['sabotage'])),
      meeting: SpaceMeeting.fromJson(asMap(json['meeting'])),
      events: <SpaceEvent>[
        for (final Object? row in asList(json['events']))
          if (row is Map) SpaceEvent.fromJson(asMap(row)),
      ],
      result: result.isEmpty ? null : result,
    );
  }

  final String status;

  /// `station` or `meeting`. Movement is frozen in the second.
  final String phase;

  final int serverMs;
  final SpaceSelf self;

  /// Everybody in line of sight, this player included.
  final List<SpaceCrewmate> visible;

  /// Seat order, so colours stay put even for players currently unseen.
  final List<String> seats;

  final List<SpaceBody> bodies;

  /// Crew repair progress, 0 to 1. One number, so the bar can move without
  /// anybody learning whose bar it is.
  final double taskProgress;
  final int taskDone;
  final int taskTotal;

  final SpaceSabotage? sabotage;
  final SpaceMeeting? meeting;
  final List<SpaceEvent> events;
  final Map<String, dynamic>? result;

  bool get isPlaying => status == 'playing';
  bool get isOver => status == 'completed';
  bool get inMeeting => phase == 'meeting' || meeting != null;

  /// Which colour a seat gets. Stable for the whole match.
  int colourIndexOf(String playerId) {
    final int index = seats.indexOf(playerId);
    return index < 0 ? 0 : index;
  }

  /// Which of the Space Crew this seat is, for drawing and for naming.
  ///
  /// Taken from seat order, which every client receives identically, so two
  /// players describing the same person describe the same person. Purely
  /// cosmetic — see [SpaceCrewKind].
  SpaceCrewKind crewKindOf(String playerId) =>
      SpaceCrewKind.values[colourIndexOf(playerId) % SpaceCrewKind.values.length];

  SpaceCrewmate? visibleCrewmate(String playerId) {
    for (final SpaceCrewmate mate in visible) {
      if (mate.playerId == playerId) return mate;
    }
    return null;
  }

  /// The nearest body this player is standing on top of, if any.
  SpaceBody? bodyWithin(double radius) {
    for (final SpaceBody body in bodies) {
      if ((body.position - self.position).distance <= radius) return body;
    }
    return null;
  }

  /// The nearest living crewmate this saboteur could reach, if any.
  SpaceCrewmate? targetWithin(double radius) {
    SpaceCrewmate? best;
    double bestSpan = radius;

    for (final SpaceCrewmate mate in visible) {
      if (mate.playerId == self.playerId || !mate.alive || mate.venting) continue;
      // Never a fellow saboteur: the server refuses it, so offering it would be
      // a button that does nothing.
      if (self.allies.contains(mate.playerId)) continue;

      final double span = (mate.position - self.position).distance;
      if (span <= bestSpan) {
        best = mate;
        bestSpan = span;
      }
    }
    return best;
  }
}
