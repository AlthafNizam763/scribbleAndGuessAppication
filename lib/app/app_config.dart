import 'package:flutter/foundation.dart';
import 'package:scribble_guess/models/voice_peer.dart';

/// Which deployment the binary is pointed at.
///
/// Chosen at build time with `--dart-define=FLAVOR=staging`; anything the
/// build does not recognise falls back to [AppFlavor.development] so a
/// mistyped define can never silently ship production credentials.
enum AppFlavor {
  development,
  staging,
  production;

  /// Parses the `FLAVOR` define, defaulting to [AppFlavor.development].
  static AppFlavor fromName(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'production' || 'prod' => AppFlavor.production,
      'staging' || 'stage' => AppFlavor.staging,
      _ => AppFlavor.development,
    };
  }

  /// Whether this flavor talks to real, user-facing infrastructure.
  bool get isProduction => this == AppFlavor.production;
}

/// Every build-time knob, resolved once and read through [AppConfig.current].
///
/// Nothing here is a secret. Firebase's client configuration (API key, app id,
/// project id) is public by design — it identifies the project, it does not
/// authorise anything; access is decided by Firestore rules, App Check and the
/// Cloud Functions' own permission checks. Real secrets live in the functions'
/// runtime configuration and never reach the client bundle.
@immutable
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.apiBaseUrl,
    required this.drawingSocketUrl,
    required this.useEmulators,
    required this.emulatorHost,
    required this.enableAnalytics,
    required this.enableCrashlytics,
    required this.enableAppCheck,
    required this.iceServerOverrides,
  });

  /// Builds the configuration from `--dart-define` values.
  factory AppConfig.fromEnvironment() {
    const String flavorName = String.fromEnvironment('FLAVOR');
    final AppFlavor flavor = AppFlavor.fromName(flavorName);

    const String apiOverride = String.fromEnvironment('API_BASE_URL');
    // `SOCKET_URL` is the name the backend's own environment uses, so the two
    // sides of the deployment are configured with one vocabulary.
    // `DRAWING_SOCKET_URL` is the older name and still wins if it is the only
    // one given, so existing build scripts keep working.
    const String socketOverride = String.fromEnvironment('SOCKET_URL');
    const String legacySocketOverride =
        String.fromEnvironment('DRAWING_SOCKET_URL');
    const String emulatorOverride = String.fromEnvironment(
      'USE_FIREBASE_EMULATORS',
    );
    const String emulatorHostOverride = String.fromEnvironment('EMULATOR_HOST');

    // The emulator suite is the default for development builds so a fresh
    // checkout never writes to a shared project by accident.
    //
    // Read as a string, not `bool.fromEnvironment`: that cannot tell "unset"
    // from "explicitly false", so the override could only ever switch the
    // emulators *on*. Anyone debugging on a physical device — where the
    // emulator host below is unreachable — needs it to switch them off.
    final bool useEmulators = switch (emulatorOverride.trim().toLowerCase()) {
      'true' || '1' || 'yes' => true,
      'false' || '0' || 'no' => false,
      _ => flavor == AppFlavor.development && !kReleaseMode,
    };

    // REST and the websocket are configured separately because in production
    // they are no longer the same origin. Socket.IO needs a process that stays
    // alive to hold a connection open, and the REST deployment is serverless —
    // it starts a function per request and tears it down after, so nothing
    // there can host a websocket. The realtime server therefore runs on its
    // own host; see `deployedRealtimeUrl`.
    //
    // Running everything locally through `server.ts` puts both back on one
    // address, which is what the single `API_BASE_URL` override still does.
    final String apiBaseUrl =
        apiOverride.isNotEmpty ? apiOverride : _defaultApiUrl(flavor);

    // `SOCKET_URL` wins, then the older `DRAWING_SOCKET_URL`.
    //
    // Then — and this is what keeps local development working — an
    // `API_BASE_URL` given on its own carries the socket with it. Someone
    // running the backend locally types one address:
    //
    //   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
    //
    // and means "talk to this backend", not "REST here, websocket on the
    // production host". Falling through to the flavor default would do the
    // latter, and the failure would be baffling: REST succeeds, the socket
    // connects to the deployed server, and the handshake is then rejected
    // because the local backend signed the token with a different
    // `JWT_SECRET`. `server.ts` serves both halves on that one port anyway.
    //
    // Naming both defines still splits them, which is what the deployment
    // itself does.
    final String socketUrl =
        switch ((socketOverride, legacySocketOverride, apiOverride)) {
      (final String s, _, _) when s.isNotEmpty => s,
      (_, final String s, _) when s.isNotEmpty => s,
      (_, _, final String s) when s.isNotEmpty => s,
      _ => _defaultSocketUrl(flavor, apiBaseUrl),
    };

    return AppConfig(
      flavor: flavor,
      apiBaseUrl: apiBaseUrl,
      drawingSocketUrl: socketUrl,
      useEmulators: useEmulators,
      emulatorHost: emulatorHostOverride.isNotEmpty
          ? emulatorHostOverride
          : _defaultEmulatorHost(),
      // Telemetry is off outside production: local experiments should never
      // pollute production dashboards or crash-free-user rates.
      enableAnalytics: flavor.isProduction,
      enableCrashlytics: flavor.isProduction && !kDebugMode,
      enableAppCheck: !useEmulators,
      iceServerOverrides: _iceServerOverrides(),
    );
  }

  /// Build-time ICE servers for voice chat, normally empty.
  ///
  /// The backend supplies the real list over `s:voice:state`, which is what
  /// keeps a TURN credential out of the app bundle and lets it be rotated
  /// without a release. These defines exist for one case the wire cannot
  /// cover: pointing a debug build at a Coturn running on the same laptop
  /// before the backend has been configured to advertise it.
  ///
  /// ```
  /// flutter run \
  ///   --dart-define=WEBRTC_STUN_URL=stun:192.168.1.20:3478 \
  ///   --dart-define=WEBRTC_TURN_URL=turn:192.168.1.20:3478 \
  ///   --dart-define=WEBRTC_TURN_USERNAME=dev \
  ///   --dart-define=WEBRTC_TURN_CREDENTIAL=dev
  /// ```
  ///
  /// Never put a production credential here: a `--dart-define` is compiled
  /// into the binary and is readable by anybody who has it.
  static List<IceServer> _iceServerOverrides() {
    const String stun = String.fromEnvironment('WEBRTC_STUN_URL');
    const String turn = String.fromEnvironment('WEBRTC_TURN_URL');
    const String turnUser = String.fromEnvironment('WEBRTC_TURN_USERNAME');
    const String turnSecret = String.fromEnvironment('WEBRTC_TURN_CREDENTIAL');

    List<String> split(String value) => <String>[
          for (final String entry in value.split(','))
            if (entry.trim().isNotEmpty) entry.trim(),
        ];

    final List<IceServer> servers = <IceServer>[];

    final List<String> stunUrls = split(stun);
    if (stunUrls.isNotEmpty) servers.add(IceServer(urls: stunUrls));

    final List<String> turnUrls = split(turn);
    if (turnUrls.isNotEmpty) {
      servers.add(
        IceServer(
          urls: turnUrls,
          username: turnUser.isEmpty ? null : turnUser,
          credential: turnSecret.isEmpty ? null : turnSecret,
        ),
      );
    }

    return List<IceServer>.unmodifiable(servers);
  }

  /// The flavor this binary was built for.
  final AppFlavor flavor;

  /// Origin of the game backend's REST API.
  ///
  /// This is the authority for everything the app does: guest sign-in, the
  /// profile, the leaderboard, and — through the websocket on the same origin
  /// — rooms, rounds, drawing, guessing and scoring.
  final String apiBaseUrl;

  /// Origin of the realtime drawing transport (Socket.IO).
  ///
  /// Drawing is the one channel too chatty for Firestore (§22), so it runs
  /// over its own websocket while Firebase stays the authority for game state.
  final String drawingSocketUrl;

  /// Whether to route Firebase traffic to the local emulator suite.
  final bool useEmulators;

  /// Host the emulator suite is reachable at from this device.
  final String emulatorHost;

  final bool enableAnalytics;
  final bool enableCrashlytics;
  final bool enableAppCheck;

  /// Build-time ICE servers for voice chat. Empty in every normal build.
  ///
  /// Consulted by `VoiceChatService` only when the server sent none, so a
  /// configured backend always wins over whatever a build was compiled with.
  final List<IceServer> iceServerOverrides;

  /// The configuration this process was launched with.
  static final AppConfig current = AppConfig.fromEnvironment();

  /// `10.0.2.2` is how the Android emulator reaches the host loopback;
  /// every other platform can use `localhost` directly.
  ///
  /// Neither address means anything on a *physical* phone. Debugging on real
  /// hardware needs either `--dart-define=EMULATOR_HOST=<your LAN IP>`, with
  /// the suite bound to `0.0.0.0`, or `--dart-define=USE_FIREBASE_EMULATORS=false`
  /// to talk to the real project instead.
  static String _defaultEmulatorHost() {
    if (kIsWeb) return 'localhost';
    return defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
  }

  /// The deployed backend, and the one place its address is written down.
  ///
  /// Everything else that needs it — [apiBaseUrl], [drawingSocketUrl],
  /// `AppConstants.defaultServerUrl`, the settings screen's reset button —
  /// resolves back to this constant, so moving the deployment is a one-line
  /// change. No trailing slash: callers join paths onto it.
  ///
  /// The REST API and the websocket share this origin: the backend attaches
  /// Socket.IO to the same HTTP server Next.js serves from, so one address
  /// covers both.
  static const String deployedBackendUrl =
      'https://scribble-and-guess-web.vercel.app';

  /// Where the realtime (Socket.IO) server is deployed.
  ///
  /// This is deliberately *not* [deployedBackendUrl]. That deployment is
  /// serverless: it starts a function to answer a request and tears it down
  /// afterwards, so it can never hold a websocket open, and its `/api/health`
  /// reported `socket: detached` for exactly that reason. Socket.IO runs on a
  /// host that keeps a process alive instead — this one, which serves
  /// `socket-server.ts` and answers `/api/health` with
  /// `{"service":"realtime","socket":"attached"}`.
  ///
  /// Both deployments read the same `MONGODB_URI` and sign with the same
  /// `JWT_SECRET`, so the token `POST /api/auth/guest` mints on
  /// [deployedBackendUrl] is what authenticates the handshake here. That
  /// shared secret is the whole reason the split is invisible to the player.
  ///
  /// No trailing slash, and no `/socket.io` suffix: that path is the Socket.IO
  /// client's own default, and appending it here would make the client request
  /// `/socket.io/socket.io/`, which 404s.
  ///
  /// A build can always override it without editing this file:
  ///
  /// ```
  /// flutter run --dart-define=SOCKET_URL=https://your-realtime-host
  /// ```
  ///
  /// Emptying it again falls back to [apiBaseUrl], which is correct only for a
  /// local `server.ts` — that one really does serve REST and the websocket on
  /// a single port. Against the deployed serverless API the fallback cannot
  /// connect, and [realtimeOriginLooksUnconfigured] flags it so the failure is
  /// reported as a configuration problem rather than a dead network.
  static const String deployedRealtimeUrl =
      'https://scribbleandguessweb.onrender.com';

  /// Where the game backend lives.
  ///
  /// The deployed backend is the default for *every* flavor, development
  /// included. A checkout that is simply run — `flutter run`, no defines —
  /// therefore talks to the real deployment rather than to a loopback address
  /// nothing is listening on, which is what a developer without a local
  /// backend actually wants.
  ///
  /// Running against a local backend is opt-in and explicit:
  ///
  /// ```
  /// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
  /// ```
  ///
  /// `10.0.2.2` is how the Android emulator reaches the host loopback;
  /// `localhost` works everywhere else. Neither means anything on a *physical*
  /// device, which needs the machine's LAN address and a backend bound to
  /// `0.0.0.0` — the `HOST` value in the backend's `.env`. The settings screen
  /// exposes the same override at runtime, which is the practical way to point
  /// two real phones at one laptop.
  static String _defaultApiUrl(AppFlavor flavor) {
    return switch (flavor) {
      AppFlavor.staging => 'https://api-staging.scribbleandguess.app',
      AppFlavor.production || AppFlavor.development => deployedBackendUrl,
    };
  }

  /// Where the realtime server lives, per flavor.
  ///
  /// Structured to mirror [_defaultApiUrl]: each flavor names its own host, so
  /// a flavor's socket always lands on the deployment that mints the tokens it
  /// presents. Staging is checked *before* [deployedRealtimeUrl] for exactly
  /// that reason — pairing the staging REST API with the production realtime
  /// host would send a staging-signed JWT to a server holding a different
  /// `JWT_SECRET`, and every handshake would come back `AUTH_ERROR`.
  ///
  /// Production and development share the deployed realtime host, and fall
  /// back to the REST origin only when none is configured — correct for a
  /// local `server.ts`, wrong against the deployed serverless API, and
  /// [realtimeOriginLooksUnconfigured] tells those two apart.
  static String _defaultSocketUrl(AppFlavor flavor, String apiBaseUrl) {
    return switch (flavor) {
      AppFlavor.staging => 'https://realtime-staging.scribbleandguess.app',
      AppFlavor.production || AppFlavor.development =>
        deployedRealtimeUrl.isNotEmpty ? deployedRealtimeUrl : apiBaseUrl,
    };
  }

  /// Whether the socket is pointed at the serverless REST deployment.
  ///
  /// That combination cannot work — a serverless function cannot hold a
  /// websocket open — and it is the single most likely misconfiguration,
  /// because it is what the app does when no realtime host has been set. The
  /// socket layer reports it as a configuration error rather than letting it
  /// surface as an unexplained connection failure.
  ///
  /// A local backend is exempt: `server.ts` really does serve both on one
  /// port, so sharing an origin there is correct.
  bool get realtimeOriginLooksUnconfigured {
    if (drawingSocketUrl != apiBaseUrl) return false;
    final Uri? uri = Uri.tryParse(apiBaseUrl);
    if (uri == null) return false;
    const Set<String> local = <String>{
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
      '0.0.0.0',
    };
    if (local.contains(uri.host) || uri.host.isEmpty) return false;
    // A LAN address is a developer's own machine running `server.ts`.
    if (RegExp(r'^(10|192\.168|172\.(1[6-9]|2\d|3[01]))\.').hasMatch(uri.host)) {
      return false;
    }
    return true;
  }

  @override
  String toString() =>
      'AppConfig(${flavor.name}, api: $apiBaseUrl, '
      'socket: $drawingSocketUrl)';
}

/// Ports the emulator suite binds, mirroring `firebase.json`.
abstract final class EmulatorPorts {
  static const int auth = 9099;
  static const int firestore = 8080;
  static const int functions = 5001;
  static const int storage = 9199;
}
