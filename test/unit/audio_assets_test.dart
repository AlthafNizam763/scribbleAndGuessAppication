import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/services/sound_service.dart';
import 'package:yaml/yaml.dart';

/// Every sound the app can ask for, checked against the disk and the manifest.
///
/// ## Why this is worth a test
///
/// A missing sound asset fails *silently*. `AudioCache` throws somewhere on a
/// platform thread, the service swallows it — deliberately, because a game
/// that would not start over a speaker is worse than a quiet one — and the
/// effect simply never plays. Nobody notices until somebody asks why the dice
/// have no sound, months later.
///
/// Two ways it can break, and both are covered here: the file is not on disk,
/// or it is on disk in a folder `pubspec.yaml` never declared, in which case
/// it is not in the bundle at all.
void main() {
  final Directory assets = Directory('assets');

  group('the generated sound files', () {
    test('every effect names a file that exists', () {
      final List<String> missing = <String>[
        for (final SoundEffect effect in SoundEffect.values)
          if (!File('${assets.path}/${effect.asset}').existsSync())
            '${effect.name} -> ${effect.asset}',
      ];

      expect(missing, isEmpty, reason: 'run: dart run tool/generate_sound_assets.dart');
    });

    test('every folder an effect uses is declared in pubspec', () {
      // Present on disk is not the same as present in the bundle. A folder
      // that is not listed under `flutter: assets:` ships nothing, and the
      // failure is invisible at runtime.
      final YamlMap pubspec =
          loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
      final YamlList declared =
          (pubspec['flutter'] as YamlMap)['assets'] as YamlList;

      final Set<String> bundled = <String>{
        for (final Object? entry in declared) entry.toString(),
      };

      for (final SoundEffect effect in SoundEffect.values) {
        // Declarations are directories with a trailing slash.
        expect(
          bundled,
          contains('assets/${effect.folder}/'),
          reason: '${effect.name} lives in an undeclared folder',
        );
      }
    });

    test('keeps every file small enough to ship', () {
      // These are short blips that live in the bundle, not streamed music.
      // Anything over a hundred kilobytes is a mistake in the score — a note
      // left ringing for ten seconds — rather than a deliberate choice.
      for (final SoundEffect effect in SoundEffect.values) {
        final int bytes = File('${assets.path}/${effect.asset}').lengthSync();
        expect(bytes, lessThan(100 * 1024), reason: effect.name);
        expect(bytes, greaterThan(100), reason: '${effect.name} is empty');
      }
    });

    test('ships no sound the app cannot play', () {
      // The other direction: a file in a game's folder that no `SoundEffect`
      // names is dead weight in the bundle, and usually a rename that was only
      // half done.
      final Set<String> referenced = <String>{
        for (final SoundEffect effect in SoundEffect.values) effect.asset,
      };

      final Set<String> folders = <String>{
        for (final SoundEffect effect in SoundEffect.values) effect.folder,
      };

      final List<String> orphans = <String>[];
      for (final String folder in folders) {
        final Directory dir = Directory('${assets.path}/$folder');
        if (!dir.existsSync()) continue;
        for (final FileSystemEntity file in dir.listSync()) {
          if (file is! File || !file.path.endsWith('.wav')) continue;
          final String name = file.uri.pathSegments.last;
          if (!referenced.contains('$folder/$name')) orphans.add('$folder/$name');
        }
      }

      expect(orphans, isEmpty);
    });

    test('plays every sound it ships', () {
      // The third way this can break, and the one the two tests above miss
      // entirely: the file is on disk, the enum names it, the bundle carries
      // it -- and nothing ever calls it. That is a sound generated, shipped
      // and never heard, which is exactly what happened to four of Kazhutha's
      // and Ludo's before this test existed.
      //
      // Crude on purpose. A grep across `lib/` for `SoundEffect.<name>`
      // cannot prove the call site is reachable, and does not try to; what it
      // proves is that somebody wired the effect to something, which is the
      // failure that actually occurs. A precise version would need the
      // analyzer and would catch nothing more.
      final StringBuffer source = StringBuffer();
      for (final FileSystemEntity entity
          in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // The enum's own declaration names every value, so reading it would
        // make this test pass unconditionally.
        if (entity.path.endsWith('sound_service.dart')) continue;
        source.write(entity.readAsStringSync());
      }
      final String body = source.toString();

      final List<String> silent = <String>[
        for (final SoundEffect effect in SoundEffect.values)
          if (!body.contains('SoundEffect.${effect.name}')) effect.name,
      ];

      expect(
        silent,
        isEmpty,
        reason: 'generated, bundled, and never played',
      );
    });
  });
}
