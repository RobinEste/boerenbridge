import 'dart:math';

/// Grappige opmerkingen generator voor verschillende spelsituaties
class GameComments {
  static final _random = Random();

  // ===========================================================================
  // RONDE-EINDE OPMERKINGEN PER SPELER
  // ===========================================================================

  /// Perfecte score (bid == tricks)
  static const _perfectBid = [
    'Netjes! 🎯',
    'Die zag je aankomen!',
    'Boerenverstand!',
    'Precies goed ingeschat',
    'Als een echte pro',
    'Keurig!',
    'Zo doe je dat',
  ];

  /// Nul geboden en nul gehaald
  static const _perfectZero = [
    'De kunst van niets doen',
    'Zen-master 🧘',
    'Strategisch wegduiken',
    'Slim gespeeld!',
    'Onzichtbaar gebleven',
  ];

  /// Flink overgeboden (bid - tricks >= 3)
  static const _bigOverbid = [
    'Optimisme is ook wat waard...',
    'Grote mond, kleine broek 👖',
    'Iets te enthousiast?',
    'Die kaarten vielen tegen',
    'Volgende keer iets bescheidener?',
  ];

  /// Licht overgeboden (bid - tricks == 1 of 2)
  static const _slightOverbid = [
    'Net niet!',
    'Bijna...',
    'Eentje tekort',
    'Pech gehad',
  ];

  /// Flink ondergeboden (tricks - bid >= 3)
  static const _bigUnderbid = [
    'Vals bescheiden! 😏',
    'Stiekem goed bezig',
    'Sandbagger!',
    'Je kaarten waren beter dan gedacht',
    'Bescheidenheid siert de mens... niet',
  ];

  /// Licht ondergeboden (tricks - bid == 1 of 2)
  static const _slightUnderbid = [
    'Eentje teveel gepakt',
    'Oeps, net iets te goed',
    'Die had je niet verwacht',
  ];

  /// Hoogste score van de ronde
  static const _roundWinner = [
    'Rondewinnaar! 👑',
    'De baas!',
    'Lekker bezig',
    'Aan kop!',
  ];

  /// Laagste score van de ronde
  static const _roundLoser = [
    'Kopje op!',
    'Volgende ronde beter',
    'Het kan verkeren',
    'Iedereen heeft zo\'n dag',
  ];

  // ===========================================================================
  // TEAM OPMERKINGEN (HELE GROEP)
  // ===========================================================================

  /// Exact geboden als groep
  static const _teamExact = [
    'Iemand gaat huilen! 😬',
    'Dit wordt spannend...',
    'Geen ruimte voor fouten',
    'Precies genoeg slagen',
  ];

  /// Flink overgeboden als groep
  static const _teamOverbid = [
    'Collectief optimisme! 🎈',
    'Wie gaat er nat?',
    'Te veel chiefs, te weinig slagen',
    'Iemand moet inleveren',
  ];

  /// Flink ondergeboden als groep
  static const _teamUnderbid = [
    'Bescheiden groepje 😇',
    'Onverwachte slagen incoming',
    'Iemand krijgt een bonus',
  ];

  // ===========================================================================
  // SPEL-EINDE OPMERKINGEN
  // ===========================================================================

  /// Winnaar van het spel
  static const _gameWinner = [
    'Kampioen! 🏆',
    'De beste boer!',
    'Verdiende winnaar',
    'Heer van de kaarten',
  ];

  /// Grote voorsprong (margin >= 30)
  static const _dominantWin = [
    'Dominante overwinning!',
    'Dat was niet eens spannend',
    'Heerst en regeert',
    'Klasse apart',
  ];

  /// Nipte overwinning (margin <= 5)
  static const _closeWin = [
    'Op het nippertje!',
    'Dat was close! 😅',
    'Hartkloppingen!',
    'Net aan!',
  ];

  /// Tweede plaats
  static const _runnerUp = [
    'Bijna!',
    'Volgende keer!',
    'Zilver is ook mooi',
    'Net niet genoeg',
  ];

  /// Laatste plaats
  static const _lastPlace = [
    'Iemand moet laatste zijn',
    'Volgende keer beter!',
    'Eervolle laatste',
    'De weg omhoog is vrij',
  ];

  // ===========================================================================
  // HELPER METHODS
  // ===========================================================================

  static String _pickRandom(List<String> options) {
    return options[_random.nextInt(options.length)];
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Krijg een opmerking voor een speler aan het einde van een ronde
  static String? getPlayerRoundComment({
    required int bid,
    required int tricksTaken,
    required int roundScore,
    required bool isRoundWinner,
    required bool isRoundLoser,
    required int totalPlayers,
  }) {
    final difference = bid - tricksTaken;

    // Perfecte nul
    if (bid == 0 && tricksTaken == 0) {
      return _pickRandom(_perfectZero);
    }

    // Perfect geboden
    if (difference == 0 && roundScore > 0) {
      return _pickRandom(_perfectBid);
    }

    // Flink overgeboden
    if (difference >= 3) {
      return _pickRandom(_bigOverbid);
    }

    // Licht overgeboden
    if (difference > 0) {
      return _pickRandom(_slightOverbid);
    }

    // Flink ondergeboden
    if (difference <= -3) {
      return _pickRandom(_bigUnderbid);
    }

    // Licht ondergeboden
    if (difference < 0) {
      return _pickRandom(_slightUnderbid);
    }

    // Ronde winnaar (alleen als geen andere opmerking)
    if (isRoundWinner && totalPlayers > 2) {
      return _pickRandom(_roundWinner);
    }

    // Ronde verliezer (alleen als geen andere opmerking)
    if (isRoundLoser && totalPlayers > 2) {
      return _pickRandom(_roundLoser);
    }

    return null;
  }

  /// Krijg een team opmerking gebaseerd op totaal geboden
  static String? getTeamComment({
    required int bidDifference,
  }) {
    // Exact geboden
    if (bidDifference == 0) {
      return _pickRandom(_teamExact);
    }

    // Flink overgeboden
    if (bidDifference >= 3) {
      return _pickRandom(_teamOverbid);
    }

    // Flink ondergeboden
    if (bidDifference <= -3) {
      return _pickRandom(_teamUnderbid);
    }

    return null;
  }

  /// Krijg een opmerking voor een speler aan het einde van het spel
  static String? getPlayerGameEndComment({
    required int rank, // 0 = winnaar, 1 = tweede, etc.
    required int totalScore,
    required int? winnerScore,
    required int totalPlayers,
  }) {
    // Winnaar
    if (rank == 0) {
      // Check voor dominante overwinning
      if (totalPlayers > 1 && winnerScore != null) {
        // We hebben geen tweede score hier, dus alleen basis winnaar comment
        return _pickRandom(_gameWinner);
      }
      return _pickRandom(_gameWinner);
    }

    // Tweede plaats
    if (rank == 1 && totalPlayers > 2) {
      return _pickRandom(_runnerUp);
    }

    // Laatste plaats
    if (rank == totalPlayers - 1 && totalPlayers > 2) {
      return _pickRandom(_lastPlace);
    }

    return null;
  }

  /// Krijg een opmerking over de winnaar met marge
  static String? getWinnerMarginComment({
    required int margin,
  }) {
    if (margin >= 30) {
      return _pickRandom(_dominantWin);
    }
    if (margin <= 5 && margin > 0) {
      return _pickRandom(_closeWin);
    }
    return null;
  }
}
