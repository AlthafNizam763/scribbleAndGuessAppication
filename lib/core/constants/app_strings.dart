/// Every user-facing string in the app.
///
/// Widgets never hard-code copy: they read it from here so wording stays
/// consistent and can be reviewed in one place.
abstract final class AppStrings {
  // ---------------------------------------------------------------------------
  // Common
  // ---------------------------------------------------------------------------

  /// Product name shown in the app bar and on the splash screen.
  static const String appName = 'Scribble & Guess';

  /// One-line pitch shown under the logo.
  static const String appTagline = 'Draw it. Guess it. Win it.';

  /// Generic confirmation action.
  static const String ok = 'OK';

  /// Generic dismissive action.
  static const String cancel = 'Cancel';

  /// Generic affirmative answer.
  static const String yes = 'Yes';

  /// Generic negative answer.
  static const String no = 'No';

  /// Action that closes a sheet or dialog.
  static const String close = 'Close';

  /// Action that goes one step back.
  static const String back = 'Back';

  /// Action that goes one step forward.
  static const String next = 'Next';

  /// Action that stores pending edits.
  static const String save = 'Save';

  /// Action that discards pending edits.
  static const String discard = 'Discard';

  /// Action that removes something permanently.
  static const String delete = 'Delete';

  /// Action that opens an editor for the current item.
  static const String edit = 'Edit';

  /// Action that repeats a failed operation.
  static const String retry = 'Retry';

  /// Action that copies a value to the clipboard.
  static const String copy = 'Copy';

  /// Confirmation shown after a successful copy.
  static const String copied = 'Copied to clipboard';

  /// Action that opens the platform share sheet.
  static const String share = 'Share';

  /// Action that leaves the current room.
  static const String leave = 'Leave';

  /// Action that finishes a flow.
  static const String done = 'Done';

  /// Action that skips an optional step.
  static const String skip = 'Skip';

  /// Placeholder shown while content is being fetched.
  static const String loading = 'Loading...';

  /// Placeholder shown while the app waits for the server.
  static const String pleaseWait = 'Hang on a second...';

  /// Neutral empty-state title reused across lists.
  static const String nothingHere = 'Nothing here yet';

  // ---------------------------------------------------------------------------
  // Home
  // ---------------------------------------------------------------------------

  /// Title of the home screen.
  static const String homeTitle = 'Scribble & Guess';

  /// Button that opens the create-room flow.
  static const String homeCreateRoom = 'Create room';

  /// Button that opens the join-room flow.
  static const String homeJoinRoom = 'Join room';

  /// Button that starts a solo practice game against bots.
  static const String homePractice = 'Practice offline';

  /// Button that opens the leaderboard.
  static const String homeLeaderboard = 'Leaderboard';

  /// Button that opens the settings screen.
  static const String homeSettings = 'Settings';

  /// Button that opens the rules screen.
  static const String homeHowToPlay = 'How to play';

  /// Prompt shown above the profile card on the home screen.
  static const String homePlayingAs = 'Playing as';

  /// Action that opens the profile editor from the home screen.
  static const String homeChangeProfile = 'Change';

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  /// Title of the profile screen.
  static const String profileTitle = 'Your doodler';

  /// Label of the name field.
  static const String profileNameLabel = 'Nickname';

  /// Hint of the name field.
  static const String profileNameHint = 'Pick a nickname';

  /// Section heading above the avatar grid.
  static const String profileAvatarSection = 'Choose a character';

  /// Section heading above the avatar colour swatches.
  static const String profileColorSection = 'Choose a colour';

  /// Action that fills the profile with a random face, colour and name.
  static const String profileRandomize = 'Surprise me';

  /// Primary action of the profile screen.
  static const String profileSave = 'Save doodler';

  /// Confirmation shown after saving a profile.
  static const String profileSaved = 'Doodler saved';

  /// Title of the dialog asking to abandon unsaved profile edits.
  static const String profileDiscardTitle = 'Discard changes?';

  /// Body of the dialog asking to abandon unsaved profile edits.
  static const String profileDiscardBody =
      'Your doodler stays the way it was.';

  // ---------------------------------------------------------------------------
  // Create room
  // ---------------------------------------------------------------------------

  /// Title of the create-room screen.
  static const String createTitle = 'Create a room';

  /// Section heading for the match rules.
  static const String createRulesSection = 'Match rules';

  /// Section heading for the word bank options.
  static const String createWordsSection = 'Words';

  /// Section heading for privacy and moderation options.
  static const String createRoomSection = 'Room';

  /// Label of the player-count stepper.
  static const String createMaxPlayers = 'Players';

  /// Label of the rounds stepper.
  static const String createRounds = 'Rounds';

  /// Label of the drawing-time slider.
  static const String createDrawTime = 'Draw time';

  /// Label of the word-choice-count stepper.
  static const String createWordChoices = 'Word choices';

  /// Label of the hint-count stepper.
  static const String createHints = 'Hints per turn';

  /// Label of the word-pick-time slider.
  static const String createWordSelectTime = 'Pick time';

  /// Label of the word-mode selector.
  static const String createWordMode = 'Word mode';

  /// Label of the custom-word editor.
  static const String createCustomWords = 'Custom words';

  /// Hint of the custom-word input.
  static const String createCustomWordHint = 'Add a word and press enter';

  /// Empty state of the custom-word list.
  static const String createCustomWordsEmpty =
      'No custom words yet. Add at least five to use custom mode.';

  /// Label of the vote-kick toggle.
  static const String createAllowVoteKick = 'Allow vote kick';

  /// Label of the private-room toggle.
  static const String createPrivate = 'Private room';

  /// Explanation under the private-room toggle.
  static const String createPrivateHint = 'Only people with the code can join.';

  /// Primary action of the create-room screen.
  static const String createSubmit = 'Create room';

  /// Action that restores the recommended settings.
  static const String createReset = 'Reset to defaults';

  // ---------------------------------------------------------------------------
  // Join room
  // ---------------------------------------------------------------------------

  /// Title of the join-room screen.
  static const String joinTitle = 'Join a room';

  /// Label of the room-code field.
  static const String joinCodeLabel = 'Room code';

  /// Hint of the room-code field.
  static const String joinCodeHint = 'e.g. K7QRA';

  /// Helper text under the room-code field.
  static const String joinCodeHelp =
      'Five characters. Letters and numbers only.';

  /// Primary action of the join-room screen.
  static const String joinSubmit = 'Join';

  /// Action that reuses the previously joined room code.
  static const String joinLastRoom = 'Rejoin last room';

  /// Action that pastes a code from the clipboard.
  static const String joinPaste = 'Paste code';

  // ---------------------------------------------------------------------------
  // Lobby
  // ---------------------------------------------------------------------------

  /// Title of the lobby screen.
  static const String lobbyTitle = 'Lobby';

  /// Label above the room-code chip.
  static const String lobbyRoomCode = 'Room code';

  /// Action that copies the room code.
  static const String lobbyCopyCode = 'Copy code';

  /// Action that shares an invite.
  static const String lobbyInvite = 'Invite friends';

  /// Section heading above the player list.
  static const String lobbyPlayers = 'Players';

  /// Action that marks the local player as ready.
  static const String lobbyReady = 'I am ready';

  /// Action that clears the ready state.
  static const String lobbyNotReady = 'Not ready';

  /// Host action that begins the match.
  static const String lobbyStart = 'Start game';

  /// Host action that opens the settings sheet.
  static const String lobbySettings = 'Room settings';

  /// Status shown to non-hosts while waiting.
  static const String lobbyWaitingForHost =
      'Waiting for the host to start the game';

  /// Status shown when there are not enough players yet.
  static const String lobbyNeedMorePlayers =
      'At least two doodlers are needed to start.';

  /// Empty state of the player list.
  static const String lobbyEmptyPlayers = 'Nobody else is here yet';

  /// Badge marking the room host.
  static const String lobbyHostBadge = 'Host';

  /// Badge marking a player who is ready.
  static const String lobbyReadyBadge = 'Ready';

  /// Title of the confirm dialog shown when leaving a room.
  static const String lobbyLeaveTitle = 'Leave the room?';

  /// Body of the confirm dialog shown when leaving a room.
  static const String lobbyLeaveBody =
      'You lose your seat and your score for this match.';

  /// Message shown when the host closes the room.
  static const String lobbyRoomClosed = 'The host closed the room.';

  // ---------------------------------------------------------------------------
  // Game
  // ---------------------------------------------------------------------------

  /// Title of the game screen.
  static const String gameTitle = 'Round';

  /// Banner shown during the pre-round countdown.
  static const String gameGetReady = 'Get ready!';

  /// Prompt shown to the drawer while picking a word.
  static const String gameChooseWord = 'Choose a word to draw';

  /// Status shown to guessers while the drawer picks a word.
  static const String gameWaitingForWord = 'The drawer is picking a word';

  /// Label above the masked word for guessers.
  static const String gameGuessThis = 'Guess this';

  /// Label above the revealed word for the drawer.
  static const String gameYouDraw = 'You are drawing';

  /// Status shown while another player draws.
  static const String gameWatching = 'Watching';

  /// Announcement shown when the drawer runs out of time.
  static const String gameTimeUp = 'Time is up!';

  /// Status shown while a started game is on hold for want of players.
  static const String gamePaused = 'Waiting for more players...';

  /// Explains the hold, and what ends it.
  static const String gamePausedBody =
      'The game is on hold until somebody else joins. Share the room code and '
      'it picks up right where it stopped.';

  /// Announcement shown to a player who guessed correctly.
  static const String gameYouGuessedIt = 'You got it!';

  /// Toolbar label for the pen tool.
  static const String gamePen = 'Pen';

  /// Toolbar label for the eraser tool.
  static const String gameEraser = 'Eraser';

  /// Toolbar label for the undo action.
  static const String gameUndo = 'Undo';

  /// Toolbar label for the redo action.
  static const String gameRedo = 'Redo';

  /// Toolbar label for the clear-canvas action.
  static const String gameClear = 'Clear';

  /// Toolbar label for the colour picker.
  static const String gameColors = 'Colours';

  /// Toolbar label for the brush-size picker.
  static const String gameBrush = 'Brush size';

  /// Title of the confirm dialog shown before clearing the canvas.
  /// Opens the full tool tray.
  static const String gameTools = 'Tools';

  /// Title of the tool tray sheet.
  static const String gameToolsTitle = 'Drawing tools';

  /// Opens the custom colour picker.
  static const String gameCustomColor = 'Custom colour';

  /// Label above the brush size slider.
  static const String gameBrushSize = 'Brush size';

  /// Explains what the fill tool actually does, since it is not a flood fill.
  static const String gameFillHint = 'Fill covers the whole canvas.';

  static const String gameClearTitle = 'Clear the canvas?';

  /// Body of the confirm dialog shown before clearing the canvas.
  static const String gameClearBody = 'Every stroke of this turn is erased.';

  /// Title of the confirm dialog shown when quitting a live match.
  static const String gameQuitTitle = 'Quit the match?';

  /// Body of the confirm dialog shown when quitting a live match.
  static const String gameQuitBody =
      'The round keeps going without you and your score is lost.';

  /// Label of the button that opens the players sheet on compact screens.
  static const String gamePlayersSheet = 'Players';

  /// Label of the button that opens the chat sheet on compact screens.
  static const String gameChatSheet = 'Chat';

  // ---------------------------------------------------------------------------
  // Chat
  // ---------------------------------------------------------------------------

  /// Title of the chat panel.
  static const String chatTitle = 'Chat';

  /// Hint of the chat input for guessers.
  static const String chatGuessHint = 'Type your guess';

  /// Hint of the chat input for the drawer, who may not guess.
  static const String chatDrawerHint = 'You cannot guess your own word';

  /// Hint of the chat input for players who already guessed the word.
  static const String chatGuessedHint = 'Chat with the other guessers';

  /// Semantic and tooltip label of the send button.
  static const String chatSend = 'Send';

  /// Empty state of the chat list.
  static const String chatEmpty = 'Say hello!';

  /// System line shown when a guess is very close to the word.
  static const String chatCloseGuess = 'So close!';

  /// Notice shown to a muted player.
  static const String chatMuted = 'You are muted in this room.';

  // ---------------------------------------------------------------------------
  // Voice chat
  // ---------------------------------------------------------------------------

  /// Status shown to the drawer, who cannot speak or hear this turn.
  static const String voiceDrawerStatus = 'Drawing — Voice disabled';

  /// Why a voice action was refused for the drawer.
  static const String voiceDrawerDisabled =
      'Voice chat is off while you are drawing.';

  /// Tooltip on the microphone button while the microphone is live.
  static const String voiceMute = 'Mute microphone';

  /// Tooltip on the microphone button while the microphone is muted.
  static const String voiceUnmute = 'Unmute microphone';

  /// Label while the voice mesh is still being set up.
  static const String voiceConnecting = 'Connecting voice...';

  /// Shown when the player refused the microphone permission.
  static const String voiceNoPermission = 'Microphone access is off';

  /// Body of the prompt asking the player to grant the microphone.
  static const String voicePermissionBody =
      'Allow microphone access in your device settings to talk to the other '
      'guessers. You can still play and type without it.';

  /// Shown when the device has no usable microphone.
  static const String voiceNoMicrophone = 'No microphone available';

  /// Shown when voice is off because the round is not running.
  static const String voiceOff = 'Voice off';

  /// Accessibility label for the indicator that somebody is talking.
  static const String voiceSomeoneSpeaking = 'Someone is speaking';

  /// Generic voice failure, for anything the service could not name.
  static const String voiceFailed = 'Voice chat is unavailable right now.';

  // ---------------------------------------------------------------------------
  // Results
  // ---------------------------------------------------------------------------

  /// Title of the round-result screen.
  static const String resultsRoundTitle = 'Round over';

  /// Title of the final-result screen.
  static const String resultsFinalTitle = 'Final scores';

  /// Label above the revealed word.
  static const String resultsWordWas = 'The word was';

  /// Section heading above the per-round score deltas.
  static const String resultsThisRound = 'This round';

  /// Section heading above the running totals.
  static const String resultsTotals = 'Totals';

  /// Status shown while the next turn is being prepared.
  static const String resultsNextRoundSoon = 'Next turn starting soon...';

  /// Line shown when nobody guessed the word.
  static const String resultsNobodyGuessed = 'Nobody guessed it.';

  /// Host action that restarts the match with the same players.
  static const String resultsPlayAgain = 'Play again';

  /// Action that returns to the home screen.
  static const String resultsBackHome = 'Back to home';

  /// Celebration shown to the player who finished first.
  static const String resultsYouWon = 'You won!';

  // ---------------------------------------------------------------------------
  // Leaderboard
  // ---------------------------------------------------------------------------

  /// Title of the leaderboard screen.
  static const String leaderboardTitle = 'Leaderboard';

  /// Column heading for the ranking numeral.
  static const String leaderboardRank = 'Rank';

  /// Column heading for the accumulated score.
  static const String leaderboardScore = 'Score';

  /// Column heading for the number of finished matches.
  static const String leaderboardGames = 'Games';

  /// Column heading for the number of won matches.
  static const String leaderboardWins = 'Wins';

  /// Label of the best single-round score.
  static const String leaderboardBestRound = 'Best round';

  /// Empty state of the leaderboard.
  static const String leaderboardEmpty =
      'Play a match to land on the leaderboard.';

  /// Action that wipes the local leaderboard.
  static const String leaderboardClear = 'Clear leaderboard';

  /// Title of the confirm dialog for wiping the leaderboard.
  static const String leaderboardClearTitle = 'Clear the leaderboard?';

  /// Body of the confirm dialog for wiping the leaderboard.
  static const String leaderboardClearBody =
      'All local scores are deleted. This cannot be undone.';

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  /// Title of the settings screen.
  static const String settingsTitle = 'Settings';

  /// Section heading for audio and haptics.
  static const String settingsFeedbackSection = 'Feedback';

  /// Section heading for look and feel.
  static const String settingsAppearanceSection = 'Appearance';

  /// Section heading for app information.
  static const String settingsAboutSection = 'About';

  /// Label of the sound toggle.
  static const String settingsSound = 'Sound effects';

  /// Label of the haptics toggle.
  static const String settingsHaptics = 'Vibration';

  /// Label of the reduced-motion toggle.
  static const String settingsReducedMotion = 'Reduce motion';

  /// Explanation under the reduced-motion toggle.
  static const String settingsReducedMotionHint =
      'Turns off animations across the app.';

  /// Label of the theme selector.
  static const String settingsTheme = 'Theme';

  /// Light theme option.
  static const String settingsThemeLight = 'Light';

  /// Dark theme option.
  static const String settingsThemeDark = 'Dark';

  /// System theme option.
  static const String settingsThemeSystem = 'System';

  /// Heading of the language section.
  static const String settingsLanguageSection = 'Language';

  /// Label of the language selector.
  static const String settingsLanguage = 'App language';

  /// What choosing a language changes.
  static const String settingsLanguageHint =
      'Changes the app text, dates, number formats and, for Arabic, the '
      'direction the whole layout runs in.';

  /// Label of the version row.
  static const String settingsVersion = 'Version';

  /// Action that erases every locally stored preference.
  static const String settingsResetAll = 'Reset all data';

  /// Title of the confirm dialog for erasing local data.
  static const String settingsResetTitle = 'Reset all data?';

  /// Body of the confirm dialog for erasing local data.
  static const String settingsResetBody =
      'Your doodler, settings and leaderboard are deleted from this device.';

  // ---------------------------------------------------------------------------
  // How to play
  // ---------------------------------------------------------------------------

  /// Title of the rules screen.
  static const String howToPlayTitle = 'How to play';

  /// Lead paragraph of the rules screen.
  static const String howToPlayIntro =
      'Scribble & Guess is a party game for two to twelve doodlers. Every turn '
      'one player draws a secret word while everybody else races to guess it.';

  /// Heading of the turn-order rule.
  static const String howToPlayTurnsTitle = '1. Take turns';

  /// Body of the turn-order rule.
  static const String howToPlayTurnsBody =
      'Players draw one after another. A round is finished once everybody has '
      'drawn once, and a match runs for as many rounds as the host picked.';

  /// Heading of the word-choice rule.
  static const String howToPlayWordTitle = '2. Pick a word';

  /// Body of the word-choice rule.
  static const String howToPlayWordBody =
      'The drawer gets a short list of words and picks one. If the pick timer '
      'runs out, the game picks for them.';

  /// Heading of the drawing rule.
  static const String howToPlayDrawTitle = '3. Draw it';

  /// Body of the drawing rule.
  static const String howToPlayDrawBody =
      'Use the pen, the eraser and the colour palette. No letters, no numbers '
      'and no arrows pointing at the answer.';

  /// Heading of the guessing rule.
  static const String howToPlayGuessTitle = '4. Guess it';

  /// Body of the guessing rule.
  static const String howToPlayGuessBody =
      'Type guesses into the chat. Spelling is forgiving: a guess that is one '
      'letter off is flagged as close. Correct guesses stay hidden from the '
      'players who are still guessing.';

  /// Heading of the scoring rule.
  static const String howToPlayScoreTitle = '5. Score points';

  /// Body of the scoring rule.
  static const String howToPlayScoreBody =
      'Guessers earn more the faster they answer, and the first correct guess '
      'gets a bonus. The drawer earns points for every player who guesses the '
      'word, so draw clearly.';

  /// Heading of the hint rule.
  static const String howToPlayHintTitle = '6. Watch for hints';

  /// Body of the hint rule.
  static const String howToPlayHintBody =
      'Letters are revealed as the timer drains. Spaces and hyphens are always '
      'visible and never count as hints.';

  /// Heading of the etiquette section.
  static const String howToPlayFairTitle = 'Play fair';

  /// Body of the etiquette section.
  static const String howToPlayFairBody =
      'Be kind in chat. Hosts can mute, kick and ban, and any player can '
      'report someone who spoils the fun.';

  // ---------------------------------------------------------------------------
  // Moderation
  // ---------------------------------------------------------------------------

  /// Action that removes a player from the room.
  static const String moderationKick = 'Kick';

  /// Action that removes a player and blocks them from returning.
  static const String moderationBan = 'Ban';

  /// Action that silences a player in chat.
  static const String moderationMute = 'Mute';

  /// Action that lets a muted player chat again.
  static const String moderationUnmute = 'Unmute';

  /// Action that hands the host role to another player.
  static const String moderationTransferHost = 'Make host';

  /// Action that starts a kick vote.
  static const String moderationVoteKick = 'Start kick vote';

  /// Action that flags a player for review.
  static const String moderationReport = 'Report';

  /// Title of the kick confirm dialog.
  static const String moderationKickTitle = 'Kick this player?';

  /// Body of the kick confirm dialog.
  static const String moderationKickBody = 'They can join again with the code.';

  /// Title of the ban confirm dialog.
  static const String moderationBanTitle = 'Ban this player?';

  /// Body of the ban confirm dialog.
  static const String moderationBanBody =
      'They cannot rejoin this room for the rest of the match.';

  /// Title of the host-transfer confirm dialog.
  static const String moderationTransferTitle = 'Hand over the host role?';

  /// Body of the host-transfer confirm dialog.
  static const String moderationTransferBody =
      'They will control the settings and the start button.';

  /// Title of the report sheet.
  static const String moderationReportTitle = 'Report a player';

  /// Hint of the report-reason field.
  static const String moderationReportHint = 'What happened?';

  /// Confirmation shown after a report is sent.
  static const String moderationReportSent = 'Report sent. Thanks for helping.';

  /// Message shown to a player who was kicked.
  static const String moderationYouWereKicked =
      'You were removed from the room.';

  /// Message shown to a player who was banned.
  static const String moderationYouWereBanned =
      'You were banned from the room.';

  // ---------------------------------------------------------------------------
  // Errors: one message per AppErrorCode, plus connection status copy
  // ---------------------------------------------------------------------------

  /// Message for `AppErrorCode.unknown`.
  static const String errorUnknown = 'Something went wrong. Please try again.';

  /// Message for `AppErrorCode.network`.
  static const String errorNetwork =
      'No connection. Check your network and try again.';

  /// Message for `AppErrorCode.timeout`.
  static const String errorTimeout = 'The server took too long to answer.';

  /// Message for `AppErrorCode.serverError`.
  static const String errorServer = 'The server ran into a problem.';

  /// Message for `AppErrorCode.connectionLost`.
  static const String errorConnectionLost = 'Connection lost. Reconnecting...';

  /// Message for `AppErrorCode.roomNotFound`.
  static const String errorRoomNotFound = 'No room with that code.';

  /// Message for `AppErrorCode.roomFull`.
  static const String errorRoomFull = 'That room is full.';

  /// Message for `AppErrorCode.gameInProgress`.
  static const String errorGameInProgress =
      'That match already started. Try again when it ends.';

  /// Message for `AppErrorCode.nameTaken`.
  static const String errorNameTaken =
      'Somebody in the room already uses that name.';

  /// Message for `AppErrorCode.invalidCode`.
  static const String errorInvalidCode = 'That room code does not look right.';

  /// Message for `AppErrorCode.banned`.
  static const String errorBanned = 'You are banned from that room.';

  /// Message for `AppErrorCode.kicked`.
  static const String errorKicked = 'You were removed from that room.';

  /// Message for `AppErrorCode.notHost`.
  static const String errorNotHost = 'Only the host can do that.';

  /// Message for `AppErrorCode.notDrawer`.
  static const String errorNotDrawer = 'Only the drawer can do that.';

  /// Message for `AppErrorCode.invalidAction`.
  static const String errorInvalidAction = 'That action is not allowed now.';

  /// Message for `AppErrorCode.validation`.
  static const String errorValidation = 'Please check the highlighted fields.';

  /// Message for `AppErrorCode.storage`.
  static const String errorStorage = 'Could not save data on this device.';

  /// Title of the connection-lost error screen.
  static const String errorConnectionTitle = 'Connection lost';

  /// Shown when the socket cannot be opened but the REST backend answers.
  ///
  /// The distinction matters to the player: their phone's network is fine, so
  /// "check your network" would send them to fix something that is not broken.
  /// The game server is what is unreachable, and waiting is the right advice.
  static const String errorRealtimeUnreachable =
      'Cannot reach the game server. It may be starting up — try again in a '
      'moment.';

  /// Shown when the backend is up but its database is not.
  ///
  /// Nothing the player can do, and retrying immediately will not help, so the
  /// copy says so rather than inviting them to hammer the button.
  static const String errorBackendDegraded =
      'The game server is having trouble. Please try again shortly.';

  /// Title of the room-not-found error screen.
  static const String errorRoomNotFoundTitle = 'Room not found';

  /// Title of the room-full error screen.
  static const String errorRoomFullTitle = 'Room is full';

  /// Status shown while the socket is opening.
  static const String statusConnecting = 'Connecting...';

  /// Status shown while the socket retries.
  static const String statusReconnecting = 'Reconnecting...';

  /// Status shown when the socket gave up.
  static const String statusOffline = 'Offline';

  /// Status shown when the socket is live.
  static const String statusConnected = 'Connected';

  // Validation ----------------------------------------------------------------

  /// Shown when a required nickname is empty.
  static const String validationNameRequired = 'Pick a nickname first.';

  /// Shown when a nickname is shorter than the minimum.
  static const String validationNameTooShort =
      'Nicknames need at least 2 characters.';

  /// Shown when a nickname is longer than the maximum.
  static const String validationNameTooLong =
      'Nicknames can be at most 16 characters.';

  /// Shown when a nickname contains unsupported characters.
  static const String validationNameInvalid =
      'Use letters, numbers, spaces, dots, hyphens or underscores.';

  /// Shown when a room code is empty.
  static const String validationCodeRequired = 'Enter a room code.';

  /// Shown when a room code has the wrong length.
  static const String validationCodeLength = 'Room codes are 5 characters.';

  /// Shown when a room code contains characters outside the alphabet.
  static const String validationCodeInvalid =
      'Room codes never contain O, 0, I or 1.';

  /// Shown when a chat message is empty.
  static const String validationMessageRequired = 'Type something first.';

  /// Shown when a chat message is too long.
  static const String validationMessageTooLong =
      'Messages can be at most 120 characters.';

  /// Shown when a custom word is empty.
  static const String validationWordRequired = 'Type a word first.';

  /// Shown when a custom word is too short.
  static const String validationWordTooShort =
      'Words need at least 2 characters.';

  /// Shown when a custom word is too long.
  static const String validationWordTooLong =
      'Words can be at most 24 characters.';

  /// Shown when a custom word contains unsupported characters.
  static const String validationWordInvalid =
      'Use letters, spaces and hyphens only.';

  /// Shown when a server address is empty.
  static const String validationUrlRequired = 'Enter a server address.';

  /// Shown when a server address cannot be parsed.
  static const String validationUrlInvalid =
      'Use a full address such as http://localhost:3000';

  // ---------------------------------------------------------------------------
  // Accessibility: semantic labels for icon-only controls and painters
  // ---------------------------------------------------------------------------

  /// Semantic label of the back button.
  static const String a11yBack = 'Go back';

  /// Semantic label of the close button.
  static const String a11yClose = 'Close';

  /// Semantic label of the settings button.
  static const String a11ySettings = 'Open settings';

  /// Semantic label of an avatar doodle.
  static const String a11yAvatar = 'Player avatar';

  /// Semantic label of the host crown marker.
  static const String a11yHost = 'Host';

  /// Semantic label of the drawing-pencil marker.
  static const String a11yDrawing = 'Currently drawing';

  /// Semantic label of the correct-guess marker.
  static const String a11yGuessedCorrectly = 'Guessed the word';

  /// Semantic label of the connection dot.
  static const String a11yConnection = 'Connection state';

  /// Semantic label of the countdown timer.
  static const String a11yTimer = 'Time left in this turn';

  /// Semantic label of the drawing surface for the drawer.
  static const String a11yCanvasDrawer =
      'Drawing canvas. Draw with one finger.';

  /// Semantic label of the drawing surface for guessers.
  static const String a11yCanvasViewer =
      'Drawing canvas of the current drawer.';

  /// Semantic label of the colour picker.
  static const String a11yColorPicker = 'Colour picker';

  /// Semantic label of the brush-size picker.
  static const String a11yBrushPicker = 'Brush size picker';

  /// Semantic label of the chat list.
  static const String a11yChatList = 'Chat messages';

  /// Semantic label of the scoreboard.
  static const String a11yScoreBoard = 'Scoreboard';

  /// Semantic label of the moderation overflow menu.
  static const String a11yPlayerMenu = 'Player actions';

  // ---------------------------------------------------------------------------
  // Relative time suffixes
  // ---------------------------------------------------------------------------

  /// Shown for timestamps within the last few seconds.
  static const String timeNow = 'now';

  /// Suffix for a whole number of seconds.
  static const String timeSecondsSuffix = 's';

  /// Suffix for a whole number of minutes.
  static const String timeMinutesSuffix = 'm';

  /// Suffix for a whole number of hours.
  static const String timeHoursSuffix = 'h';

  /// Suffix for a whole number of days.
  static const String timeDaysSuffix = 'd';

  /// Suffix for a whole number of weeks.
  static const String timeWeeksSuffix = 'w';

  /// Suffix for a whole number of years.
  static const String timeYearsSuffix = 'y';

  // ---------------------------------------------------------------------------
  // Interpolated and pluralised helpers
  // ---------------------------------------------------------------------------

  /// Pluralised player count, such as `3 players`.
  static String playersCount(int n) => n == 1 ? '1 player' : '$n players';

  /// Seat usage of a room, such as `4/8 players`.
  static String playersOfMax(int n, int max) => '$n/$max players';

  /// Pluralised round count, such as `3 rounds`.
  static String roundsCount(int n) => n == 1 ? '1 round' : '$n rounds';

  /// Pluralised point count, such as `120 points`.
  static String pointsCount(int n) => n == 1 ? '1 point' : '$n points';

  /// Signed score delta, such as `+120`.
  static String pointsDelta(int n) => n >= 0 ? '+$n' : '$n';

  /// Pluralised hint count, such as `2 hints`.
  static String hintsCount(int n) => n == 1 ? '1 hint' : '$n hints';

  /// Pluralised word count, such as `7 words`.
  static String wordsCount(int n) => n == 1 ? '1 word' : '$n words';

  /// Pluralised finished-match count, such as `9 games`.
  static String gamesCount(int n) => n == 1 ? '1 game' : '$n games';

  /// Pluralised win count, such as `2 wins`.
  static String winsCount(int n) => n == 1 ? '1 win' : '$n wins';

  /// Pluralised letter count, such as `6 letters`.
  static String lettersCount(int n) => n == 1 ? '1 letter' : '$n letters';

  /// Duration setting value, such as `80 seconds`.
  static String secondsValue(int n) => n == 1 ? '1 second' : '$n seconds';

  /// Progress label of a match, such as `Round 2 of 3`.
  static String roundOf(int current, int total) => 'Round $current of $total';

  /// Turn heading, such as `Anna is drawing`.
  static String isDrawing(String name) => '$name is drawing';

  /// Countdown before a turn starts, such as `Starting in 3`.
  static String startingIn(int seconds) => 'Starting in $seconds';

  /// Reveal of the secret word, such as `The word was banana`.
  static String wordWas(String word) => 'The word was $word';

  /// System chat line for a correct guess.
  static String guessedTheWord(String name) => '$name guessed the word!';

  /// System chat line for a player joining.
  static String playerJoined(String name) => '$name joined';

  /// System chat line for a player leaving.
  static String playerLeft(String name) => '$name left';

  /// System chat line for a host change.
  static String hostIsNow(String name) => '$name is the host now';

  /// System chat line for a kicked player.
  static String playerKicked(String name) => '$name was kicked';

  /// System chat line for a banned player.
  static String playerBanned(String name) => '$name was banned';

  /// Vote-kick progress, such as `Kick Anna? 2/4 votes`.
  static String voteKickProgress(String name, int votes, int needed) =>
      'Kick $name? $votes/$needed votes';

  /// Placement line on the results screen, such as `2nd place`.
  static String placement(int rank) => '${ordinal(rank)} place';

  /// English ordinal for a rank, such as `1st`, `2nd` or `13th`.
  static String ordinal(int n) {
    final int mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) {
      return '${n}th';
    }
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  /// Invite text shared from the lobby.
  static String inviteMessage(String code) =>
      'Join my Scribble & Guess room! Code: $code';

  /// Version row value, such as `Version 1.0.0`.
  static String versionLabel(String version) => 'Version $version';

  /// Retry countdown of the reconnect banner.
  static String reconnectingIn(int seconds) => 'Reconnecting in ${seconds}s';

  // ---------------------------------------------------------------------------
  // Quick Play
  // ---------------------------------------------------------------------------

  /// The Play button at rest.
  static const String quickPlay = 'Play now';

  /// Subtitle under the Play button.
  static const String quickPlayHint = 'Drop into a public room';

  /// Establishing the session and the socket.
  static const String quickPlayConnecting = 'Connecting...';

  /// Asking the server for a room.
  static const String quickPlayFinding = 'Finding a room...';

  /// A room was found and the seat is being taken.
  static const String quickPlayJoining = 'Joining room...';

  /// Nothing was waiting, so a room is being opened.
  static const String quickPlayCreating = 'Creating room...';

  /// Shown when Quick Play failed and can be retried.
  static const String quickPlayFailed = 'Could not find a room. Try again.';

  /// Shown when a room was opened rather than joined.
  static const String quickPlayOpened =
      'Opened a new room. Others can join you now.';

  // ---------------------------------------------------------------------------
  // Leaderboard scopes
  // ---------------------------------------------------------------------------

  /// Column heading for the proportion of games won.
  static const String leaderboardWinRate = 'Win rate';

  /// Pinned footer showing where the local player stands.
  static const String leaderboardYourRank = 'Your rank';

  /// Shown in the pinned footer when the player has not finished a game.
  static const String leaderboardUnranked = 'Play a match to get ranked';

  /// Empty state of the friends leaderboard.
  static const String leaderboardFriendsEmpty =
      'Add friends to see how you compare.';

  /// Empty state of the locality leaderboard when a city is set.
  static const String leaderboardLocalityEmpty =
      'Nobody else from your area has played yet.';

  /// Prompt shown on the locality board when no city is set.
  static const String leaderboardNeedsLocality =
      'Add your city to your profile to see who is playing nearby.';

  /// Action on the locality prompt.
  static const String leaderboardSetLocality = 'Set my city';

  /// Heading of the local, on-device history.
  static const String leaderboardLocalHistory = 'This device';

  // ---------------------------------------------------------------------------
  // Friends
  // ---------------------------------------------------------------------------

  /// Title of the friends screen, and the button that opens it.
  static const String friendsTitle = 'Friends';

  /// Tab showing accepted friends.
  static const String friendsTabFriends = 'Friends';

  /// Tab showing incoming and outgoing requests.
  static const String friendsTabRequests = 'Requests';

  /// Tab showing blocked players.
  static const String friendsTabBlocked = 'Blocked';

  /// Title of the requests screen.
  static const String friendRequestsTitle = 'Friend requests';

  /// Heading above requests waiting on the local player.
  static const String friendRequestsIncoming = 'Waiting on you';

  /// Heading above requests the local player sent.
  static const String friendRequestsOutgoing = 'Waiting on them';

  /// Empty state of the friends list.
  static const String friendsEmpty =
      'No friends yet. Search for someone to add.';

  /// Empty state of the requests list.
  static const String friendRequestsEmpty = 'No requests right now.';

  /// Empty state of the blocked list.
  static const String friendsBlockedEmpty = 'You have not blocked anyone.';

  /// Placeholder of the user search field.
  static const String friendsSearchHint = 'Search players by name';

  /// Empty state of a search that matched nobody.
  static const String friendsSearchEmpty = 'No players found.';

  /// Prompt shown before a search term is typed.
  static const String friendsSearchPrompt =
      'Type at least two letters to find a player.';

  /// Action that sends a friend request.
  static const String friendAdd = 'Add friend';

  /// State of a request that has been sent and not answered.
  static const String friendRequested = 'Request sent';

  /// Action that withdraws a sent request.
  static const String friendCancelRequest = 'Cancel request';

  /// Action that accepts an incoming request.
  static const String friendAccept = 'Accept';

  /// Action that declines an incoming request.
  static const String friendReject = 'Reject';

  /// State shown when two players are already friends.
  static const String friendsAlready = 'Friends';

  /// Action that ends a friendship.
  static const String friendRemove = 'Remove friend';

  /// Action that blocks a player.
  static const String friendBlock = 'Block';

  /// State shown when a player is blocked.
  static const String friendBlocked = 'Blocked';

  /// Action that lifts a block.
  static const String friendUnblock = 'Unblock';

  /// Title of the confirm dialog for ending a friendship.
  static const String friendRemoveTitle = 'Remove this friend?';

  /// Body of the confirm dialog for ending a friendship.
  ///
  /// Names the player, because this dialog can be reached from a list where
  /// several rows look alike and "remove this friend" would not say which.
  static String friendRemoveBody(String name) =>
      'You and $name will no longer be friends. Either of you can send a new '
      'request later.';

  /// Title of the confirm dialog for blocking a player.
  static const String friendBlockTitle = 'Block this player?';

  /// Body of the confirm dialog for blocking a player.
  static const String friendBlockBody =
      'They will be removed from your friends, any pending request is '
      'cancelled, and you will not be matched together in Quick Play.';

  /// Title of the confirm dialog for lifting a block.
  static const String friendUnblockTitle = 'Unblock this player?';

  /// Body of the confirm dialog for lifting a block.
  static const String friendUnblockBody =
      'They will be able to send you a friend request again. You will not '
      'automatically become friends.';

  /// Title of the profile screen for another player.
  static const String playerProfileTitle = 'Player';

  /// Label of the world ranking row on a profile.
  static const String playerProfileRank = 'World rank';

  /// Shown in place of a rank for a player who has not finished a game.
  static const String playerProfileUnranked = 'Unranked';

  /// Label of the locality row on a profile.
  static const String playerProfileLocality = 'Plays from';

  // ---------------------------------------------------------------------------
  // Locality
  // ---------------------------------------------------------------------------

  /// Section heading for the optional location fields on the profile screen.
  static const String localitySection = 'Where you play from';

  /// Explanation under the locality section.
  static const String localityHint =
      'Optional, and only ever a town. It puts you on the local leaderboard.';

  /// Label of the city field.
  static const String localityCity = 'City';

  /// Label of the region field.
  static const String localityRegion = 'Region';

  /// Label of the country field.
  static const String localityCountry = 'Country code';

  /// Helper text of the country field.
  static const String localityCountryHint = 'Two letters, like IN or DE';

  // ---------------------------------------------------------------------------
  // Location detection
  // ---------------------------------------------------------------------------

  /// Primary action: fill the town in from the device.
  static const String locationUse = 'Use my location';

  /// The same action once a town is already set.
  static const String locationUpdate = 'Update location';

  /// Heading of the location section in Settings.
  static const String settingsLocationSection = 'Location';

  /// Settings row that runs the detection flow.
  static const String locationSettingsRow = 'Update location';

  /// Subtitle of that row.
  static const String locationSettingsHint =
      'Refresh the town your locality leaderboard uses.';

  /// Busy label while a fix is being read.
  static const String locationDetecting = 'Finding your town…';

  /// Title of the explanation shown before the permission dialog.
  static const String locationNoticeTitle = 'Use your location?';

  /// The explanation itself, shown before anything is requested.
  ///
  /// Written to be read, not skimmed past: it says what is taken, what is
  /// kept, what is not kept, and that saying no costs nothing. Every claim in
  /// it is one the code actually enforces — see `LocationService`.
  static const String locationNoticeBody =
      'Scribble & Guess can fill in your town for you.\n\n'
      '• Your device works out roughly where you are, and we turn that into '
      'a town name on your phone.\n'
      '• Only the town, region and country are saved — never your exact '
      'position, your address, or any history of where you have been.\n'
      '• It happens once, when you tap the button. Nothing runs in the '
      'background.\n'
      '• It is used only for the locality leaderboard. Other players see the '
      'town, and nothing finer.\n\n'
      'You can say no and type your town instead, or skip it entirely.';

  /// Confirm action on the explanation.
  static const String locationNoticeAllow = 'Continue';

  /// Dismiss action on the explanation.
  static const String locationNoticeNotNow = 'Not now';

  /// Confirmation after a town was detected and saved.
  static const String locationSaved = 'Saved.';

  /// Shown when the player declines the system permission dialog.
  static const String locationDeniedHint =
      'No problem — you can type your town below instead.';

  /// Title of the prompt shown after a permanent denial.
  static const String locationBlockedTitle = 'Location is turned off for '
      'Scribble & Guess';

  /// Body of that prompt.
  static const String locationBlockedBody =
      'Your phone will not ask again until you change it in system settings. '
      'You can also just type your town instead.';

  /// Action that opens the app's system settings page.
  static const String locationOpenSettings = 'Open settings';

  /// Title of the prompt shown when device location is switched off.
  static const String locationOffTitle = 'Location is switched off';

  /// Body of that prompt.
  static const String locationOffBody =
      'Turn location on in your phone settings to fill your town in '
      'automatically, or type it below instead.';

  /// Shown when a fix resolved to nowhere in particular.
  static const String locationNotFound =
      'Could not work out which town that is. Try typing it instead.';

  /// Shown when the fix or the lookup failed outright.
  static const String locationFailed =
      'Could not find your town just now. Try again, or type it below.';

  /// Shown on a build with no geocoder — the web app.
  static const String locationUnsupported =
      'This version cannot detect your town. Type it below instead.';

  /// Reveals the manual fields.
  static const String locationEnterManually = 'Enter it myself';

  /// Hides them again.
  static const String locationHideManual = 'Hide these fields';

  /// Action that removes the saved town.
  static const String locationClear = 'Remove my town';

  /// Title of the confirmation before clearing.
  static const String locationClearTitle = 'Remove your town?';

  /// Body of that confirmation.
  static const String locationClearBody =
      'You will come off the locality leaderboard. Your scores are not '
      'affected.';

  /// Shown once the town has been removed.
  static const String locationCleared = 'Removed.';

  /// Label above the town currently saved.
  static const String locationCurrent = 'Your town';

  /// Shown in place of a town when none is set.
  static const String locationNoneSet = 'Not set';

  // ---------------------------------------------------------------------------
  // Room invitations and the public room browser
  // ---------------------------------------------------------------------------

  /// Title of the invite sheet opened from the lobby.
  static const String inviteSheetTitle = 'Invite friends';

  /// Line under that title, naming the room being invited into.
  static const String inviteSheetSubtitle = 'They will get an invitation now.';

  /// The Invite button on a friend's row.
  static const String inviteAction = 'Invite';

  /// State of a friend who has already been asked.
  static const String inviteSent = 'Invited';

  /// State of a friend who is already in the room.
  static const String inviteJoined = 'Joined';

  /// Shown beside a friend with a device connected.
  static const String inviteOnline = 'Online';

  /// Shown beside a friend with no device connected.
  static const String inviteOffline = 'Offline';

  /// Empty state of the invite sheet.
  static const String inviteNoFriends =
      'No friends yet. Add some, then invite them here.';

  /// Confirmation after an invitation goes out.
  static const String inviteSentToast = 'Invitation sent.';

  /// Title of the incoming invitation dialog and of the inbox screen.
  static const String invitationsTitle = 'Room invitations';

  /// Title of the pop-up that appears when an invitation arrives.
  static const String invitationTitle = 'You are invited';

  /// Accepts an invitation.
  static const String invitationAccept = 'Accept';

  /// Declines an invitation.
  static const String invitationReject = 'Reject';

  /// Dismisses the pop-up without answering, leaving it in the inbox.
  static const String invitationLater = 'Later';

  /// Empty state of the invitations inbox.
  static const String invitationsEmpty = 'No invitations right now.';

  /// Label above the room on an invitation card.
  static const String invitationRoom = 'Room';

  /// Label above the player count on an invitation card.
  static const String invitationPlayers = 'Players';

  /// Marks a room that anybody can find in the browser.
  static const String invitationPublic = 'Public';

  /// Marks a room reachable only by its code or an invitation.
  static const String invitationPrivate = 'Private';

  /// Shown after declining.
  static const String invitationRejected = 'Invitation declined.';

  /// Title of the public room browser, and the button that opens it.
  static const String publicRoomsTitle = 'Public rooms';

  /// Line under that title.
  static const String publicRoomsSubtitle =
      'Open rooms waiting for players. Tap one to join.';

  /// Empty state of the browser.
  static const String publicRoomsEmpty =
      'No open rooms right now. Start one and friends can join you.';

  /// The Join button on a room card.
  static const String publicRoomsJoin = 'Join';

  /// Prefix naming who is hosting a room.
  static const String publicRoomsHostedBy = 'Hosted by';

  /// Shown on the browser when the player already holds a seat elsewhere.
  static const String publicRoomsLeaveFirst =
      'You are already in another room. Leave that room first.';

  /// Action on that notice, which takes the player back to their room.
  static const String publicRoomsBackToRoom = 'Back to my room';

  /// Header above the member list in the lobby.
  static const String roomMembersTitle = 'In this room';

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  /// Title of the notification centre.
  static const String notificationsTitle = 'Notifications';

  /// Tooltip on the bell in the home screen's app bar.
  static const String notificationsOpen = 'Open notifications';

  /// Empty state of the whole inbox.
  static const String notificationsEmpty =
      'Nothing yet. Friend requests and invitations show up here.';

  /// Empty state when the unread filter is on and the backlog is clear.
  static const String notificationsAllRead = 'You are all caught up.';

  /// Filter chip narrowing the list to unread rows.
  static const String notificationsUnreadOnly = 'Unread only';

  /// Clears the whole backlog.
  static const String notificationsMarkAllRead = 'Mark all read';

  /// Confirmation after clearing the backlog.
  static const String notificationsAllMarkedRead = 'All marked as read.';

  /// Removes one row.
  static const String notificationsDelete = 'Delete';

  // ---------------------------------------------------------------------------
  // Shareable results
  // ---------------------------------------------------------------------------

  /// Shares the finished match as an image.
  static const String resultShare = 'Share result';

  /// Copies the standings as text.
  static const String resultCopy = 'Copy result';

  /// Confirmation after copying.
  static const String resultCopied = 'Result copied.';

  /// Shown when sharing could not start.
  static const String resultShareFailed = 'Could not share that result.';

  /// Header above the match awards on the card.
  static const String resultAwards = 'Highlights';

  /// Award labels.
  static const String resultTopScorer = 'Top scorer';
  static const String resultBestDrawer = 'Best drawer';
  static const String resultBestGuesser = 'Best guesser';
  static const String resultFastestGuesser = 'Quickest';

  /// The line under the title on a shared card.
  static String resultSubtitle(String mode, int rounds) =>
      '$mode · $rounds rounds';

  /// Shown under a swipe-to-delete gesture.
  static const String notificationsDeleted = 'Notification deleted.';

  // ---------------------------------------------------------------------------
  // Chat extras
  // ---------------------------------------------------------------------------

  /// One-tap messages offered above the chat input.
  ///
  /// Short, positive and impossible to aim at anybody — which is the point.
  /// A quick-message list is the one part of chat that cannot be moderated
  /// after the fact, so nothing on it should be usable as an insult.
  static const List<String> chatQuickMessages = <String>[
    'Good drawing!',
    'Nice guess!',
    'Wait, I know this!',
    'GG!',
    'So close!',
    'Your turn!',
  ];

  /// The emoji a message may be reacted with. Mirrors the server's set.
  static const List<String> chatReactions = <String>[
    '👍',
    '😂',
    '🔥',
    '😮',
    '❤️',
    '👏',
  ];

  /// Shown while one other player is typing.
  static String chatTypingOne(String name) => '$name is typing…';

  /// Shown while several are.
  static const String chatTypingMany = 'Several people are typing…';

  /// Withdraws one of this player's own messages.
  static const String chatDelete = 'Delete message';

  /// Reports somebody else's message.
  static const String chatReport = 'Report message';

  /// Confirmation after a report is filed.
  static const String chatReported = 'Thanks — that has been reported.';

  /// Shown in place of the input when the host has turned chat off.
  static const String chatDisabled = 'Chat is off in this room.';

  // ---------------------------------------------------------------------------
  // Drawing replay
  // ---------------------------------------------------------------------------

  /// Title of the replay screen.
  static const String replayTitle = 'Replay';

  /// Opens the replay of the round that just ended.
  static const String replayWatch = 'Watch replay';

  /// Label above the word a replayed round was about.
  static const String replayWord = 'The word was';

  /// Prefix naming who drew the replayed round.
  static const String replayDrawnBy = 'Drawn by';

  /// Starts or resumes playback.
  static const String replayPlay = 'Play';

  /// Pauses playback.
  static const String replayPause = 'Pause';

  /// Starts again from the first stroke.
  static const String replayRestart = 'Restart';

  /// Cycles the playback speed.
  static const String replaySpeed = 'Speed';

  /// Saves or shares the drawing as an image.
  static const String replayShare = 'Share drawing';

  /// Shown while the image is being prepared.
  static const String replaySharing = 'Preparing image…';

  /// Shown when sharing could not start.
  static const String replayShareFailed = 'Could not share that drawing.';

  /// Fallback when a round has no stored drawing.
  static const String replayNoDrawing = 'Nobody drew anything this round.';

  /// Fallback when the replay could not be loaded at all.
  static const String replayUnavailable =
      'That replay is not available. It may be from a round that is still running.';

  /// Empty state of the list of a match's replays.
  static const String replayListEmpty = 'No finished rounds to replay yet.';

  /// Note shown when a drawing was thinned to fit the storage budget.
  static const String replayCompacted =
      'This drawing was simplified to save space.';

  /// One row of the replay list, e.g. `Round 2 · Ana`.
  static String replayRoundLabel(int round, String drawer) =>
      'Round $round · $drawer';

  // ---------------------------------------------------------------------------
  // Levels, XP and achievements
  // ---------------------------------------------------------------------------

  /// Title of the achievements screen.
  static const String achievementsTitle = 'Achievements';

  /// Summary line above the catalogue, e.g. `3 of 12 unlocked`.
  static String achievementsUnlockedOf(int unlocked, int total) =>
      '$unlocked of $total unlocked';

  /// Empty state, which should only ever show if the catalogue fails to load.
  static const String achievementsEmpty = 'No achievements to show yet.';

  /// Title of the XP history screen.
  static const String xpHistoryTitle = 'XP history';

  /// Empty state of the XP history.
  static const String xpHistoryEmpty =
      'No XP yet. Finish a match and it will show up here.';

  /// Header above the payout on the result screen.
  static const String progressionEarned = 'You earned';

  /// The XP line on the result screen, e.g. `+140 XP`.
  static String progressionXpEarned(int xp) => '+$xp XP';

  /// Shown when a match crossed a level boundary.
  static String progressionLevelUp(int level, String title) =>
      'Level $level — $title';

  /// Header above the achievements a match unlocked.
  static const String progressionUnlocked = 'Unlocked';

  /// Label on the profile's link to the achievements screen.
  static const String progressionViewAchievements = 'View achievements';


  // --- Practice ------------------------------------------------------------

  /// Title of the solo practice screen.
  static const String practiceTitle = 'Practice';

  /// How practice is offered on the home screen.
  static const String practiceSubtitle = 'Draw and guess on your own';

  /// Prompt above the practice word choices.
  static const String practiceChooseWord = 'Pick a word to draw';

  /// Prefix of the running practice score.
  static const String practiceScore = 'Score';

  /// Placeholder in the practice guess field.
  static const String practiceGuessHint = 'Type your guess';

  /// Shown under the guess field for a near miss.
  static const String practiceClose = 'Close!';

  /// Shown under the guess field for a miss.
  static const String practiceWrong = 'Not quite.';

  /// Heading of the practice reveal when the word was guessed.
  static const String practiceGotIt = 'Got it!';

  /// Heading of the practice reveal when the clock ran out.
  static const String practiceTimeUp = 'Time up';

  /// Moves on to another practice word.
  static const String practiceNextWord = 'Next word';

  /// Ends the practice turn early.
  static const String practiceGiveUp = 'Give up';

  /// Opens the tool tray from practice.
  static const String practiceTools = 'Tools';

  /// Undoes the last practice stroke.
  static const String practiceUndo = 'Undo';

  /// Clears the practice canvas.
  static const String practiceClear = 'Clear';

  // --- Tournaments ---------------------------------------------------------

  /// Title of the tournaments screen.
  static const String tournamentsTitle = 'Tournaments';

  /// Shown when there is nothing scheduled.
  static const String tournamentsEmpty = 'No tournaments running right now.';

  /// Registers for an event.
  static const String tournamentRegister = 'Register';

  /// Confirmation after registering.
  static const String tournamentRegistered = 'You are in. Good luck!';

  /// Marks an event the player has already entered.
  static const String tournamentRegisteredShort = 'Registered';

  /// Suffix after the entrant count.
  static const String tournamentEntrants = 'entered';

  /// Prefix before a finished event's winner.
  static const String tournamentWinner = 'Winner:';

  /// Opens an event's leaderboard.
  static const String tournamentShowBoard = 'Standings';

  /// Closes an event's leaderboard.
  static const String tournamentHideBoard = 'Hide';

  /// Shown when an event has no entrants yet.
  static const String tournamentBoardEmpty = 'Nobody has scored yet.';

  // --- Automatic tournaments -----------------------------------------------

  /// Sits under the screen title, explaining that nobody runs these.
  static const String tournamentAutoSubtitle =
      'Tournaments run themselves. Join one and play.';

  /// Shown in a slot that is between tournaments.
  static const String tournamentSlotEmpty = 'No tournament in this slot';

  /// The reassurance under [tournamentSlotEmpty].
  static const String tournamentSlotEmptyHint =
      'A new one will be created automatically soon.';

  /// Shown when every slot is empty at once.
  static const String tournamentNoneRunning = 'No tournaments running right now';

  /// The reassurance under [tournamentNoneRunning].
  static const String tournamentNoneRunningHint =
      'New tournaments are created automatically.';

  /// Label for a slot, followed by its number.
  static const String tournamentSlot = 'Slot';

  /// Status: registration is open.
  static const String tournamentStatusRegistration = 'Registration Open';

  /// Status: registration closed, players are confirming.
  static const String tournamentStatusCheckIn = 'Check-in Open';

  /// Status: matches are being played.
  static const String tournamentStatusRunning = 'Running';

  /// Status: created, about to open.
  static const String tournamentStatusUpcoming = 'Starting soon';

  /// Status: finished.
  static const String tournamentStatusCompleted = 'Completed';

  /// Status: called off.
  static const String tournamentStatusCancelled = 'Cancelled';

  /// The primary action while registration is open.
  static const String tournamentJoin = 'Join Tournament';

  /// The primary action while check-in is open.
  static const String tournamentCheckIn = 'Check In';

  /// Confirmation after checking in.
  static const String tournamentCheckedIn = 'Checked in. Your match is coming up.';

  /// Marks a player who has confirmed.
  static const String tournamentCheckedInShort = 'Checked in';

  /// Leaves a tournament before it starts.
  static const String tournamentWithdraw = 'Withdraw';

  /// Confirmation after withdrawing.
  static const String tournamentWithdrew = 'You have left the tournament.';

  /// Opens the bracket.
  static const String tournamentViewBracket = 'View Bracket';

  /// Opens the tournament detail screen.
  static const String tournamentDetails = 'Details';

  /// The primary action when a match room is open for this player.
  static const String tournamentEnterMatch = 'Enter Match';

  /// Header above the player list.
  static const String tournamentPlayers = 'Players';

  /// Label for the real-player count.
  static const String tournamentHumanPlayers = 'Players';

  /// Label for the AI count.
  static const String tournamentAiPlayers = 'AI players';

  /// The badge under an AI entrant's name.
  static const String tournamentAiPlayer = 'AI Player';

  /// Entry cost, which is always nothing.
  static const String tournamentFreeEntry = 'Free entry';

  /// The format label.
  static const String tournamentFormatKnockout = 'Knockout';

  /// Header above the rules list.
  static const String tournamentRules = 'Rules';

  /// Header above the bracket.
  static const String tournamentBracket = 'Bracket';

  /// Countdown prefix while registration is open.
  static const String tournamentClosesIn = 'Registration closes in';

  /// Countdown prefix while check-in is open.
  static const String tournamentCheckInClosesIn = 'Check-in closes in';

  /// Countdown prefix once a match room is waiting.
  static const String tournamentEnterWithin = 'Enter within';

  /// Shown on a round in progress.
  static const String tournamentRound = 'Round';

  /// Shown on a bye.
  static const String tournamentBye = 'Bye';

  /// Shown on a walkover.
  static const String tournamentWalkover = 'Walkover';

  /// Shown on a pairing whose players are not decided yet.
  static const String tournamentAwaiting = 'To be decided';

  /// Shown when the player cannot join because they are in another tournament.
  static const String tournamentAlreadyIn = 'You are already in a tournament.';

  /// Header above the placement table.
  static const String tournamentResults = 'Results';

  /// Explains that the tournament could not run.
  static const String tournamentCancelledBecause = 'Cancelled:';
}
