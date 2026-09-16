import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/models/words/word_bank.dart';

/// Small built-in word set used when a word asset cannot be read.
///
/// The bundled JSON assets are the real word bank; this compact set only has
/// to keep the game playable when an asset is missing or corrupted, so it
/// covers every [WordCategory] and every [WordDifficulty] in the four
/// Latin-script languages, with every other language falling back to English.
abstract final class FallbackWords {
  /// Builds the built-in word bank for [language].
  ///
  /// A fresh [WordBank] is created on every call, so callers that need one
  /// repeatedly should hold on to the result; `WordBankLoader` already does.
  static WordBank bank(AppLanguage language) => WordBank(
        language: language,
        byCategory: _expand(_sourceFor(language)),
      );

  /// Picks the raw word table for [language].
  ///
  /// Only the four Latin-script languages have a compiled-in table. The others
  /// (Malayalam, Hindi, Tamil, Arabic, Japanese, Russian) ship as JSON assets
  /// and live in the server word bank; if that is unreachable, falling back to
  /// English keeps the room playable, which is the entire point of a fallback.
  /// Better a round in the wrong language than a round that cannot start.
  static Map<WordCategory, Map<WordDifficulty, List<String>>> _sourceFor(
    AppLanguage language,
  ) =>
      switch (language) {
        AppLanguage.en => _english,
        AppLanguage.es => _spanish,
        AppLanguage.fr => _french,
        AppLanguage.de => _german,
        AppLanguage.ml ||
        AppLanguage.hi ||
        AppLanguage.ja ||
        AppLanguage.ta ||
        AppLanguage.ar ||
        AppLanguage.ru =>
          _english,
      };

  /// Turns a raw word table into the per-category [WordItem] lists of a bank.
  static Map<WordCategory, List<WordItem>> _expand(
    Map<WordCategory, Map<WordDifficulty, List<String>>> source,
  ) {
    final Map<WordCategory, List<WordItem>> byCategory =
        <WordCategory, List<WordItem>>{};
    for (final MapEntry<WordCategory, Map<WordDifficulty, List<String>>> entry
        in source.entries) {
      byCategory[entry.key] = <WordItem>[
        for (final MapEntry<WordDifficulty, List<String>> group
            in entry.value.entries)
          for (final String text in group.value)
            WordItem(
              text: text,
              category: entry.key,
              difficulty: group.key,
            ),
      ];
    }
    return byCategory;
  }

  /// English fallback words, twelve per category.
  static const Map<WordCategory, Map<WordDifficulty, List<String>>> _english =
      <WordCategory, Map<WordDifficulty, List<String>>>{
    WordCategory.animals: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['cat', 'dog', 'fish', 'bird'],
      WordDifficulty.medium: <String>[
        'penguin',
        'octopus',
        'giraffe',
        'squirrel',
      ],
      WordDifficulty.hard: <String>[
        'platypus',
        'chameleon',
        'armadillo',
        'hedgehog',
      ],
    },
    WordCategory.food: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['apple', 'pizza', 'cake', 'egg'],
      WordDifficulty.medium: <String>[
        'pancake',
        'popcorn',
        'avocado',
        'spaghetti',
      ],
      WordDifficulty.hard: <String>[
        'croissant',
        'pineapple',
        'cheeseburger',
        'watermelon',
      ],
    },
    WordCategory.objects: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['cup', 'book', 'chair', 'key'],
      WordDifficulty.medium: <String>[
        'umbrella',
        'backpack',
        'scissors',
        'ladder',
      ],
      WordDifficulty.hard: <String>[
        'telescope',
        'chandelier',
        'typewriter',
        'hourglass',
      ],
    },
    WordCategory.places: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['house', 'beach', 'park', 'school'],
      WordDifficulty.medium: <String>[
        'castle',
        'lighthouse',
        'airport',
        'museum',
      ],
      WordDifficulty.hard: <String>[
        'pyramid',
        'volcano',
        'windmill',
        'skyscraper',
      ],
    },
    WordCategory.movies: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Titanic', 'Frozen', 'Shrek', 'Up'],
      WordDifficulty.medium: <String>[
        'Toy Story',
        'Batman',
        'Minions',
        'Avatar',
      ],
      WordDifficulty.hard: <String>[
        'Jurassic Park',
        'Star Wars',
        'Snow White',
        'Finding Nemo',
      ],
    },
    WordCategory.sports: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['soccer', 'tennis', 'boxing', 'running'],
      WordDifficulty.medium: <String>[
        'swimming',
        'cycling',
        'baseball',
        'skiing',
      ],
      WordDifficulty.hard: <String>[
        'gymnastics',
        'snowboarding',
        'badminton',
        'archery',
      ],
    },
    WordCategory.jobs: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['chef', 'doctor', 'farmer', 'teacher'],
      WordDifficulty.medium: <String>[
        'firefighter',
        'astronaut',
        'painter',
        'mechanic',
      ],
      WordDifficulty.hard: <String>[
        'archaeologist',
        'veterinarian',
        'lifeguard',
        'blacksmith',
      ],
    },
    WordCategory.technology: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['phone', 'robot', 'laptop', 'camera'],
      WordDifficulty.medium: <String>[
        'keyboard',
        'headphones',
        'printer',
        'joystick',
      ],
      WordDifficulty.hard: <String>[
        'microscope',
        'satellite',
        'hologram',
        'smartwatch',
      ],
    },
    WordCategory.nature: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['sun', 'tree', 'cloud', 'moon'],
      WordDifficulty.medium: <String>[
        'rainbow',
        'waterfall',
        'mountain',
        'cactus',
      ],
      WordDifficulty.hard: <String>[
        'hurricane',
        'glacier',
        'avalanche',
        'canyon',
      ],
    },
  };

  /// Spanish fallback words, six per category.
  static const Map<WordCategory, Map<WordDifficulty, List<String>>> _spanish =
      <WordCategory, Map<WordDifficulty, List<String>>>{
    WordCategory.animals: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['gato', 'perro'],
      WordDifficulty.medium: <String>['pingüino', 'jirafa'],
      WordDifficulty.hard: <String>['camaleón', 'erizo'],
    },
    WordCategory.food: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['manzana', 'pizza'],
      WordDifficulty.medium: <String>['aguacate', 'sandía'],
      WordDifficulty.hard: <String>['hamburguesa', 'espaguetis'],
    },
    WordCategory.objects: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['taza', 'libro'],
      WordDifficulty.medium: <String>['paraguas', 'mochila'],
      WordDifficulty.hard: <String>['telescopio', 'reloj de arena'],
    },
    WordCategory.places: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['casa', 'playa'],
      WordDifficulty.medium: <String>['castillo', 'faro'],
      WordDifficulty.hard: <String>['pirámide', 'rascacielos'],
    },
    WordCategory.movies: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Titanic', 'Shrek'],
      WordDifficulty.medium: <String>['Batman', 'Minions'],
      WordDifficulty.hard: <String>['La Sirenita', 'Blancanieves'],
    },
    WordCategory.sports: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['fútbol', 'tenis'],
      WordDifficulty.medium: <String>['natación', 'ciclismo'],
      WordDifficulty.hard: <String>['gimnasia', 'esgrima'],
    },
    WordCategory.jobs: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['cocinero', 'médico'],
      WordDifficulty.medium: <String>['bombero', 'astronauta'],
      WordDifficulty.hard: <String>['veterinario', 'arqueólogo'],
    },
    WordCategory.technology: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['teléfono', 'robot'],
      WordDifficulty.medium: <String>['teclado', 'satélite'],
      WordDifficulty.hard: <String>['microscopio', 'holograma'],
    },
    WordCategory.nature: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['sol', 'árbol'],
      WordDifficulty.medium: <String>['arcoíris', 'cascada'],
      WordDifficulty.hard: <String>['huracán', 'avalancha'],
    },
  };

  /// French fallback words, six per category.
  static const Map<WordCategory, Map<WordDifficulty, List<String>>> _french =
      <WordCategory, Map<WordDifficulty, List<String>>>{
    WordCategory.animals: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['chat', 'chien'],
      WordDifficulty.medium: <String>['pingouin', 'girafe'],
      WordDifficulty.hard: <String>['caméléon', 'hérisson'],
    },
    WordCategory.food: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['pomme', 'pizza'],
      WordDifficulty.medium: <String>['avocat', 'pastèque'],
      WordDifficulty.hard: <String>['croissant', 'hamburger'],
    },
    WordCategory.objects: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['tasse', 'livre'],
      WordDifficulty.medium: <String>['parapluie', 'sac à dos'],
      WordDifficulty.hard: <String>['télescope', 'sablier'],
    },
    WordCategory.places: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['maison', 'plage'],
      WordDifficulty.medium: <String>['château', 'phare'],
      WordDifficulty.hard: <String>['pyramide', 'gratte-ciel'],
    },
    WordCategory.movies: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Titanic', 'Shrek'],
      WordDifficulty.medium: <String>['Batman', 'Minions'],
      WordDifficulty.hard: <String>['La Reine des Neiges', 'Blanche-Neige'],
    },
    WordCategory.sports: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['football', 'tennis'],
      WordDifficulty.medium: <String>['natation', 'cyclisme'],
      WordDifficulty.hard: <String>['gymnastique', 'escrime'],
    },
    WordCategory.jobs: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['chef', 'médecin'],
      WordDifficulty.medium: <String>['pompier', 'astronaute'],
      WordDifficulty.hard: <String>['vétérinaire', 'archéologue'],
    },
    WordCategory.technology: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['téléphone', 'robot'],
      WordDifficulty.medium: <String>['clavier', 'satellite'],
      WordDifficulty.hard: <String>['microscope', 'hologramme'],
    },
    WordCategory.nature: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['soleil', 'arbre'],
      WordDifficulty.medium: <String>['arc-en-ciel', 'cascade'],
      WordDifficulty.hard: <String>['ouragan', 'avalanche'],
    },
  };

  /// German fallback words, six per category.
  static const Map<WordCategory, Map<WordDifficulty, List<String>>> _german =
      <WordCategory, Map<WordDifficulty, List<String>>>{
    WordCategory.animals: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Katze', 'Hund'],
      WordDifficulty.medium: <String>['Pinguin', 'Giraffe'],
      WordDifficulty.hard: <String>['Chamäleon', 'Igel'],
    },
    WordCategory.food: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Apfel', 'Pizza'],
      WordDifficulty.medium: <String>['Avocado', 'Wassermelone'],
      WordDifficulty.hard: <String>['Croissant', 'Hamburger'],
    },
    WordCategory.objects: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Tasse', 'Buch'],
      WordDifficulty.medium: <String>['Regenschirm', 'Rucksack'],
      WordDifficulty.hard: <String>['Teleskop', 'Sanduhr'],
    },
    WordCategory.places: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Haus', 'Strand'],
      WordDifficulty.medium: <String>['Schloss', 'Leuchtturm'],
      WordDifficulty.hard: <String>['Pyramide', 'Wolkenkratzer'],
    },
    WordCategory.movies: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Titanic', 'Shrek'],
      WordDifficulty.medium: <String>['Batman', 'Minions'],
      WordDifficulty.hard: <String>['Die Eiskönigin', 'Schneewittchen'],
    },
    WordCategory.sports: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Fußball', 'Tennis'],
      WordDifficulty.medium: <String>['Schwimmen', 'Radfahren'],
      WordDifficulty.hard: <String>['Turnen', 'Fechten'],
    },
    WordCategory.jobs: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Koch', 'Arzt'],
      WordDifficulty.medium: <String>['Feuerwehrmann', 'Astronaut'],
      WordDifficulty.hard: <String>['Tierarzt', 'Archäologe'],
    },
    WordCategory.technology: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Telefon', 'Roboter'],
      WordDifficulty.medium: <String>['Tastatur', 'Satellit'],
      WordDifficulty.hard: <String>['Mikroskop', 'Hologramm'],
    },
    WordCategory.nature: <WordDifficulty, List<String>>{
      WordDifficulty.easy: <String>['Sonne', 'Baum'],
      WordDifficulty.medium: <String>['Regenbogen', 'Wasserfall'],
      WordDifficulty.hard: <String>['Hurrikan', 'Lawine'],
    },
  };
}
