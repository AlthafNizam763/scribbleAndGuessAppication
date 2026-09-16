# Legacy Socket.IO game server

These files implemented the **whole game** — rooms, rotation, scoring, hints,
guess matching, word secrecy — back when Socket.IO was the authoritative
backend.

They were superseded when the project migrated to Firebase. The authoritative
game engine now lives in `functions/src/`, where the same rules were ported to
TypeScript and are covered by `functions/src/services/rules.test.ts`.

They are kept here rather than deleted because they are the reference the port
was made against: if a scoring or hint behaviour ever looks wrong, this is the
implementation it is supposed to match. `legacy/test/rules.test.js` still
documents the original expectations (57 cases).

Nothing here is loaded at runtime. The live server (`server/src/`) is now only
the drawing relay described in §22 and §51 of the spec.
