import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/room_invite.dart';

/// The invitation and room-browser models, and their wire formats.
///
/// ## Why the enum tests matter more than they look
///
/// Every `fromJson` here is deliberately forgiving: a missing field produces a
/// default rather than an exception, so the invitations list survives one bad
/// row. The cost of that is that a *wrong* wire value fails silently too. An
/// invitation whose status parsed as `pending` when the server said `expired`
/// would render with live Accept and Reject buttons that can only ever be
/// refused, and the symptom would be a player tapping a button that does
/// nothing they can explain.
///
/// So the wire strings are pinned here, transcribed from the backend's
/// `INVITATION_STATUS`, and the round-trip test catches a value renamed on one
/// side and not the other.
void main() {
  group('RoomInvitationStatus wire format', () {
    test('parses the values the backend actually sends', () {
      expect(
        RoomInvitationStatus.fromName('pending'),
        RoomInvitationStatus.pending,
      );
      expect(
        RoomInvitationStatus.fromName('accepted'),
        RoomInvitationStatus.accepted,
      );
      expect(
        RoomInvitationStatus.fromName('rejected'),
        RoomInvitationStatus.rejected,
      );
      expect(
        RoomInvitationStatus.fromName('expired'),
        RoomInvitationStatus.expired,
      );
    });

    test('round-trips through its wire name', () {
      for (final RoomInvitationStatus status in RoomInvitationStatus.values) {
        expect(RoomInvitationStatus.fromName(status.wire), status);
      }
    });

    test('falls back to pending rather than throwing', () {
      expect(RoomInvitationStatus.fromName(null), RoomInvitationStatus.pending);
      expect(
        RoomInvitationStatus.fromName('something-new'),
        RoomInvitationStatus.pending,
      );
    });
  });

  group('RoomInvitation', () {
    /// The payload the server puts on `s:room:invitationReceived`.
    Map<String, dynamic> payload({Object? expiresAtMs}) => <String, dynamic>{
          'id': 'inv-1',
          'roomId': 'room-1',
          'roomCode': 'A7K9P',
          'status': 'pending',
          'inviter': <String, dynamic>{
            'id': 'u-1',
            'username': 'Ana',
            'avatarId': 3,
            'avatarColorIndex': 2,
          },
          'playerCount': 3,
          'maxPlayers': 8,
          'isPublic': true,
          'roomStatus': 'waiting',
          'createdAtMs': 1000,
          'expiresAtMs':
              expiresAtMs ?? DateTime.now().millisecondsSinceEpoch + 60000,
        };

    test('parses everything the invitation card draws', () {
      final RoomInvitation invitation = RoomInvitation.fromJson(payload());

      expect(invitation.id, 'inv-1');
      expect(invitation.roomCode, 'A7K9P');
      expect(invitation.inviter.name, 'Ana');
      expect(invitation.inviter.avatarId, 3);
      expect(invitation.playerCount, 3);
      expect(invitation.maxPlayers, 8);
      expect(invitation.isPublic, isTrue);
      expect(invitation.roomStatus, RoomStatus.waiting);
      expect(invitation.occupancy, '3/8');
    });

    test('survives a payload with nothing in it', () {
      // A malformed push must render as a placeholder, never crash the
      // listener that would then stop delivering every later invitation.
      final RoomInvitation invitation =
          RoomInvitation.fromJson(const <String, dynamic>{});

      expect(invitation.id, isEmpty);
      expect(invitation.inviter.isEmpty, isTrue);
      expect(invitation.occupancy, '0/0');
      expect(invitation.roomStatus, RoomStatus.waiting);
    });

    test('treats a past deadline as lapsed and therefore not open', () {
      final RoomInvitation lapsed = RoomInvitation.fromJson(
        payload(expiresAtMs: DateTime.now().millisecondsSinceEpoch - 1),
      );

      expect(lapsed.isLapsed, isTrue);
      expect(lapsed.isOpen, isFalse);
    });

    test('is open only while pending', () {
      for (final RoomInvitationStatus status in RoomInvitationStatus.values) {
        final RoomInvitation invitation = RoomInvitation.fromJson(
          <String, dynamic>{...payload(), 'status': status.wire},
        );

        expect(
          invitation.isOpen,
          status == RoomInvitationStatus.pending,
          reason: 'status ${status.wire}',
        );
      }
    });

    test('treats a missing deadline as not lapsed', () {
      // Zero means "the server did not say", which must not be read as
      // "expired in 1970" — that would hide every invitation from an older
      // server build.
      final RoomInvitation invitation = RoomInvitation.fromJson(
        <String, dynamic>{...payload(), 'expiresAtMs': 0},
      );

      expect(invitation.isLapsed, isFalse);
      expect(invitation.isOpen, isTrue);
    });
  });

  group('PublicRoom', () {
    test('parses a browser row', () {
      final PublicRoom room = PublicRoom.fromJson(const <String, dynamic>{
        'id': 'room-1',
        'code': 'A7K9P',
        'name': "Ana's room",
        'hostId': 'u-1',
        'hostName': 'Ana',
        'playerCount': 5,
        'maxPlayers': 8,
        'status': 'waiting',
        'rounds': 3,
        'drawTimeSeconds': 80,
        'language': 'en',
        'createdAtMs': 1000,
      });

      expect(room.name, "Ana's room");
      expect(room.hostName, 'Ana');
      expect(room.occupancy, '5/8');
      expect(room.freeSeats, 3);
      expect(room.status, RoomStatus.waiting);
      expect(room.language, AppLanguage.en);
    });

    test('never reports negative free seats', () {
      // The count is a snapshot, so it can arrive already at or past the cap
      // if the room filled between the query and the response.
      final PublicRoom room = PublicRoom.fromJson(const <String, dynamic>{
        'playerCount': 9,
        'maxPlayers': 8,
      });

      expect(room.freeSeats, 0);
    });
  });

  group('InviteCandidate', () {
    test('parses the flags the sheet draws its button from', () {
      final InviteCandidate candidate =
          InviteCandidate.fromJson(const <String, dynamic>{
        'id': 'u-2',
        'username': 'Bo',
        'avatarId': 1,
        'avatarColorIndex': 4,
        'isOnline': true,
        'isMember': false,
        'isInvited': false,
        'canInvite': true,
        'blockedReason': null,
        'lastSeenAtMs': 1000,
      });

      expect(candidate.card.name, 'Bo');
      expect(candidate.isOnline, isTrue);
      expect(candidate.canInvite, isTrue);
      expect(candidate.blockedReason, isEmpty);
    });

    test('defaults to un-invitable when the server said nothing', () {
      // The safe default: a row the server did not vouch for offers no button
      // rather than one that would be refused.
      final InviteCandidate candidate =
          InviteCandidate.fromJson(const <String, dynamic>{});

      expect(candidate.canInvite, isFalse);
      expect(candidate.isMember, isFalse);
      expect(candidate.isInvited, isFalse);
    });

    test('marking a row invited also closes its button', () {
      final InviteCandidate before =
          InviteCandidate.fromJson(const <String, dynamic>{
        'id': 'u-2',
        'username': 'Bo',
        'canInvite': true,
      });

      final InviteCandidate after = before.asInvited();

      expect(after.isInvited, isTrue);
      // Both, or the row would show "Invited" beside a live Invite button.
      expect(after.canInvite, isFalse);
      expect(after.card.id, 'u-2');
    });
  });

  group('RoomMembers', () {
    test('parses the cold-read membership snapshot', () {
      final RoomMembers members = RoomMembers.fromJson(const <String, dynamic>{
        'roomId': 'room-1',
        'roomCode': 'A7K9P',
        'hostId': 'u-1',
        'playerCount': 2,
        'maxPlayers': 8,
        'status': 'waiting',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'u-1', 'name': 'Ana', 'isHost': true},
          <String, dynamic>{'id': 'u-2', 'name': 'Bo'},
        ],
      });

      expect(members.members, hasLength(2));
      expect(members.members.first.name, 'Ana');
      expect(members.members.first.isHost, isTrue);
      expect(members.hostId, 'u-1');
    });

    test('drops a malformed member rather than failing the whole snapshot', () {
      final RoomMembers members = RoomMembers.fromJson(const <String, dynamic>{
        'members': <Object>['not-a-player'],
      });

      expect(members.members, isEmpty);
    });
  });
}
