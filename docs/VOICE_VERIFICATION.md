# Two-client voice verification

**Status: not yet run. WebRTC connection remains not physically verified.**

Everything below is a procedure, not a result. The signalling contract is
covered by automated tests (`tests/platformClientFlow.test.ts`, the
`platform voice` group) and those pass — but whether two phones actually hear
each other depends on microphones, NAT traversal and ICE, none of which exist
in a headless runner. Nobody has run this procedure on hardware.

## What is already proven, and what is not

| Claim | How | Status |
|---|---|---|
| Join returns ICE servers and the peer list | automated | passing |
| A non-member is refused with `NOT_IN_GAME` | automated | passing |
| A frame to a non-member is refused | automated | passing |
| Space Mystery refuses voice outside a meeting | automated | passing |
| Offers reach the addressed peer only | code-reviewed | **unverified** |
| Two devices exchange SDP and candidates | — | **unverified** |
| Audio is audible | — | **unverified** |
| Mute propagates between devices | — | **unverified** |
| Leaving removes the peer | code-reviewed | **unverified** |
| A reconnect rebuilds the mesh | code-reviewed | **unverified** |
| Teardown releases the microphone | code-reviewed | **unverified** |

## The instrument

Long-press the microphone button on any platform game's HUD to open the voice
checklist. It reads live state off the running `VoiceChatService` — the peer
map, each peer's connection state, the mute flags and the measured audio
levels — and shows which steps have genuinely happened **on that device**.

Nine rows, one per step of the procedure below. Seven read current state. The
last two — a peer leaving and the mesh rebuilding after a reconnect — are
transitions rather than states: each is true for an instant and false again
straight after, so those two latch when they happen and stay lit. That means
they are only observed while the panel is open, which is why step 7 onwards
says to leave it open.

Run it on both devices at once. A row green on one and not the other is the
asymmetry, and the first row that stops is where to look.

It cannot tell you whether the audio is *audible*: a track can be live,
unmuted and carrying silence. The last step is always somebody speaking and
somebody else hearing them.

## Procedure

Two devices, two accounts, the same match. Kazhutha is the simplest table to
use because its voice has no restrictions.

1. **A joins.** Tap the mic. Expect: mic open, server admitted, no peer yet.
2. **B joins.** Expect on both: peer discovered.
3. **Offer and answer.** Expect both to leave `connecting`. Exactly one side
   offers — the one with the higher id, decided by `_shouldOffer` — so if both
   are stuck at `connecting`, suspect the relay rather than the peers.
4. **ICE.** Expect "ICE connected" on both. If this is the row that stops, it
   is NAT traversal: no TURN is configured by default, so a symmetric NAT on
   either side will fail here and nowhere else. Set `WEBRTC_TURN_URL` and
   retry before concluding anything else is wrong.
5. **Audio.** A speaks; B's "audio flowing" should go green, and the peer dot
   in B's HUD should grow. Then swap.
6. **Mute.** A mutes. Expect B's "mute propagates" row to go green and A's dot
   to grey out on B's screen. Unmute and confirm it clears.
7. **Leave.** A leaves voice. Expect B's peer count to drop to zero and B's
   strip to read "alone".
8. **Reconnect.** Put A into flight mode for ten seconds and back. Expect the
   reconnect curtain, then `game:subscribe` to re-attach, then the mesh to
   rebuild without A having to press anything.
9. **Leave the room.** A leaves the match entirely. Expect A's microphone to
   release — the OS mic indicator should go out — and B to lose the peer.

## The per-game restrictions

Each of these is a *server* rule. The client cannot grant itself voice, so the
check is that the refusal arrives and the UI explains it.

| Game | Rule | How to test |
|---|---|---|
| Scribble & Guess | The drawer cannot speak or hear | Join voice as a guesser, then take the pen. Expect voice to drop and the control to read "Voice disabled" — not merely to mute. |
| Kazhutha | No restriction | Voice works for everybody, including players who have gone out. Going out is winning, not elimination. |
| Ludo | No restriction | Voice works for all four seats throughout. |
| Bluff Bar | Out of glasses, out of voice | Play until a player is eliminated. Expect their mic to drop and a join to be refused with "You are out. Listen from the bar." |
| Space Mystery | Living players, during a meeting only | Try to join while walking the ship: refused, "Voice opens when a meeting is called." Report a body: voice opens. End the meeting: every mic drops. Get eliminated: refused, "The dead do not talk to the living." |

The Space Mystery case is the one worth running carefully. It is the only game
where membership is withdrawn *during* a session rather than at a boundary,
and the reconciler that does it (`platformVoiceService.reconcile`, fired from
the engine on three transitions) is the piece most likely to have a gap.

## If something fails

- **Refused at join** — read the reason. `NOT_IN_GAME` means the seat was not
  found, which is a room problem, not a voice one. `VOICE_NOT_AVAILABLE` means
  a rule fired, and the message says which.
- **Peers stuck connecting** — the relay is addressed, so a frame goes to one
  `user:<id>` channel. Check both devices are in the voice group; a device
  that joined the room but not voice is not in it.
- **ICE fails only on some networks** — expected without TURN. Not a bug.
- **Audio one way only** — one microphone, not the mesh. Check permissions on
  the silent device.
