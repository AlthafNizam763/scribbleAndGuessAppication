/// The English parameterised patterns.
///
/// Hand-written, unlike `en.dart`, because these are the strings that take a
/// value: `AppStrings` expresses them as functions with string interpolation,
/// and interpolation cannot be translated — the placeholder has to survive
/// into the catalogue so another language can move it, or drop it, or put the
/// count after the noun instead of before.
///
/// ## Two shapes
///
/// A plain pattern is one key holding `{placeholder}` markers. A plural is a
/// family of keys suffixed with a CLDR category — `.one`, `.other`, and for
/// languages that need them `.zero`, `.two`, `.few`, `.many`. `AppText._plural`
/// picks the category and then fills `{n}`.
///
/// English needs only `one` and `other`; the count is written out in the
/// singular (`1 player`, not `{n} player`) because that is what reads well,
/// and the substitution is harmless either way.
const Map<String, String> enPatterns = <String, String>{
  // --- Counts --------------------------------------------------------------
  'playersCount.one': '1 player',
  'playersCount.other': '{n} players',
  'roundsCount.one': '1 round',
  'roundsCount.other': '{n} rounds',
  'pointsCount.one': '1 point',
  'pointsCount.other': '{n} points',
  'hintsCount.one': '1 hint',
  'hintsCount.other': '{n} hints',
  'wordsCount.one': '1 word',
  'wordsCount.other': '{n} words',
  'gamesCount.one': '1 game',
  'gamesCount.other': '{n} games',
  'winsCount.one': '1 win',
  'winsCount.other': '{n} wins',
  'lettersCount.one': '1 letter',
  'lettersCount.other': '{n} letters',
  'secondsValue.one': '1 second',
  'secondsValue.other': '{n} seconds',
  'playersOfMax': '{n}/{max} players',

  // --- Match ---------------------------------------------------------------
  'roundOf': 'Round {current} of {total}',
  'isDrawing': '{name} is drawing',
  'startingIn': 'Starting in {seconds}',
  'wordWas': 'The word was {word}',
  'guessedTheWord': '{name} guessed the word!',
  'playerJoined': '{name} joined',
  'playerLeft': '{name} left',
  'hostIsNow': '{name} is the host now',
  'playerKicked': '{name} was kicked',
  'playerBanned': '{name} was banned',
  'voteKickProgress': 'Kick {name}? {votes}/{needed} votes',
  'chatTypingOne': '{name} is typing…',

  // --- Results and progression ---------------------------------------------
  'placement': '{rank} place',
  'resultSubtitle': '{mode} · {rounds}',
  'replayRoundLabel': 'Round {round} · {drawer}',
  'achievementsUnlockedOf': '{unlocked} of {total} unlocked',
  'progressionXpEarned': '+{xp} XP',
  'progressionLevelUp': 'Level {level} — {title}',

  // --- Social and chrome ---------------------------------------------------
  'friendRemoveBody':
      'You and {name} will no longer be friends. Either of you can send a new '
          'request later.',
  'inviteMessage': 'Join my Scribble & Guess room! Code: {code}',
  'versionLabel': 'Version {version}',
  'reconnectingIn': 'Reconnecting in {seconds}s',
};
