// Boerenbridge Game Rules Configuration
// Ondersteunt alle varianten: Standaard, Vlaams, Rotterdam, etc.

// =============================================================================
// SCORING SYSTEMS
// =============================================================================

enum ScoringSystem {
  /// Standaard: +10 voor juist bod, +2 per slag, 0 bij fout
  standard,

  /// Vlaams: +10 voor juist bod, +3 per slag
  flemish,

  /// Bonus alleen: Alleen punten bij juist bod
  bonusOnly,

  /// Met penalty: Strafpunten bij fout bod (-2 per slag verschil)
  withPenalty,

  /// Nederlands met strafpunten: +10/+2 bij juist, -3 per slag verschil bij fout
  dutchWithPenalty,
}

extension ScoringSystemExtension on ScoringSystem {
  String get displayName => switch (this) {
    ScoringSystem.standard => 'Standaard (+10/+2)',
    ScoringSystem.flemish => 'Vlaams (+10/+3)',
    ScoringSystem.bonusOnly => 'Alleen bonus',
    ScoringSystem.withPenalty => 'Met strafpunten (-2)',
    ScoringSystem.dutchWithPenalty => 'Nederlands met straf (-3)',
  };

  String get description => switch (this) {
    ScoringSystem.standard => '10 punten voor juist bod, +2 per behaalde slag, 0 bij fout',
    ScoringSystem.flemish => '10 punten voor juist bod, +3 per behaalde slag',
    ScoringSystem.bonusOnly => '10 punten voor juist bod, 0 bij fout',
    ScoringSystem.withPenalty => '10 + 2×slag bij juist, -2×verschil bij fout',
    ScoringSystem.dutchWithPenalty => '10 + 2×slag bij juist, -3×verschil bij fout',
  };
}

// =============================================================================
// ROUND SEQUENCE
// =============================================================================

enum RoundSequence {
  /// 1 → max → 1 (klassiek)
  pyramid,
  
  /// 1 → max (alleen omhoog)
  ascending,
  
  /// max → 1 (alleen omlaag)
  descending,
  
  /// Custom volgorde
  custom,
}

extension RoundSequenceExtension on RoundSequence {
  String get displayName => switch (this) {
    RoundSequence.pyramid => 'Piramide (1→max→1)',
    RoundSequence.ascending => 'Oplopend (1→max)',
    RoundSequence.descending => 'Aflopend (max→1)',
    RoundSequence.custom => 'Aangepast',
  };
  
  /// Genereer de rondes voor [playerCount] spelers
  List<int> generateRounds(int playerCount, {int? customMax}) {
    final maxCards = customMax ?? (52 ~/ playerCount);
    
    return switch (this) {
      RoundSequence.pyramid => [
        for (var i = 1; i <= maxCards; i++) i,
        for (var i = maxCards - 1; i >= 1; i--) i,
      ],
      RoundSequence.ascending => [
        for (var i = 1; i <= maxCards; i++) i,
      ],
      RoundSequence.descending => [
        for (var i = maxCards; i >= 1; i--) i,
      ],
      RoundSequence.custom => [maxCards], // Override met custom
    };
  }
}

// =============================================================================
// TRUMP DETERMINATION
// =============================================================================

enum TrumpDetermination {
  /// Bovenste kaart van reststapel
  topCard,
  
  /// Roterende volgorde (♠ → ♥ → ♦ → ♣ → geen)
  rotating,
  
  /// Deler kiest
  dealerChoice,
  
  /// Geen troef
  noTrump,
}

// =============================================================================
// GAME RULES
// =============================================================================

class GameRules {
  /// Puntenberekening systeem
  final ScoringSystem scoringSystem;
  
  /// Volgorde van rondes
  final RoundSequence roundSequence;
  
  /// Custom rondes (alleen bij RoundSequence.custom)
  final List<int>? customRounds;
  
  /// Hoe wordt troef bepaald?
  final TrumpDetermination trumpDetermination;
  
  /// "Screw the dealer" - deler mag niet het verschil bieden
  final bool screwTheDealer;
  
  /// Mag je 0 slagen bieden?
  final bool allowZeroBid;
  
  /// Bonus voor 0 slagen correct voorspeld
  final int zeroBidBonus;
  
  /// Maximaal aantal kaarten per ronde (null = automatisch)
  final int? maxCardsPerRound;

  /// Maximaal aantal rondes (null = alle rondes spelen)
  final int? maxRounds;

  const GameRules({
    this.scoringSystem = ScoringSystem.standard,
    this.roundSequence = RoundSequence.pyramid,
    this.customRounds,
    this.trumpDetermination = TrumpDetermination.topCard,
    this.screwTheDealer = true,
    this.allowZeroBid = true,
    this.zeroBidBonus = 0,
    this.maxCardsPerRound,
    this.maxRounds,
  });
  
  /// Standaard Nederlandse regels
  static const dutch = GameRules(
    scoringSystem: ScoringSystem.standard,
    roundSequence: RoundSequence.pyramid,
    screwTheDealer: true,
    allowZeroBid: true,
  );
  
  /// Vlaamse variant
  static const flemish = GameRules(
    scoringSystem: ScoringSystem.flemish,
    roundSequence: RoundSequence.pyramid,
    screwTheDealer: true,
    allowZeroBid: true,
    zeroBidBonus: 5,
  );
  
  /// Snelle variant (alleen oplopend)
  static const quick = GameRules(
    scoringSystem: ScoringSystem.standard,
    roundSequence: RoundSequence.ascending,
    screwTheDealer: true,
    allowZeroBid: true,
  );
  
  /// Bereken score voor een speler deze ronde
  int calculateRoundScore(int bid, int tricksTaken) {
    final correct = bid == tricksTaken;
    final difference = (bid - tricksTaken).abs();

    return switch (scoringSystem) {
      ScoringSystem.standard => correct
          ? 10 + (tricksTaken * 2)
          : 0,
      ScoringSystem.flemish => correct
          ? 10 + (tricksTaken * 3)
          : 0,
      ScoringSystem.bonusOnly => correct ? 10 : 0,
      ScoringSystem.withPenalty => correct
          ? 10 + (tricksTaken * 2)
          : -difference * 2,
      ScoringSystem.dutchWithPenalty => correct
          ? 10 + (tricksTaken * 2)
          : -difference * 3,
    } + (correct && bid == 0 ? zeroBidBonus : 0);
  }
  
  /// Welke biedingen zijn toegestaan voor de deler?
  List<int> allowedBidsForDealer(int cardsInRound, int totalBidsSoFar) {
    final allBids = <int>[
      if (allowZeroBid) 0,
      for (var i = 1; i <= cardsInRound; i++) i,
    ];
    
    if (!screwTheDealer) return allBids;
    
    // "Screw the dealer": het totaal mag niet kloppen
    final forbidden = cardsInRound - totalBidsSoFar;
    return allBids.where((bid) => bid != forbidden).toList();
  }
  
  /// Genereer rondes voor dit spel
  List<int> getRounds(int playerCount) {
    List<int> rounds;
    if (roundSequence == RoundSequence.custom && customRounds != null) {
      rounds = customRounds!;
    } else {
      rounds = roundSequence.generateRounds(playerCount, customMax: maxCardsPerRound);
    }

    // Beperk aantal rondes indien maxRounds is ingesteld
    if (maxRounds != null && maxRounds! > 0 && rounds.length > maxRounds!) {
      rounds = rounds.sublist(0, maxRounds!);
    }

    return rounds;
  }
  
  Map<String, dynamic> toJson() => {
    'scoring_system': scoringSystem.index,
    'round_sequence': roundSequence.index,
    'custom_rounds': customRounds,
    'trump_determination': trumpDetermination.index,
    'screw_the_dealer': screwTheDealer,
    'allow_zero_bid': allowZeroBid,
    'zero_bid_bonus': zeroBidBonus,
    'max_cards_per_round': maxCardsPerRound,
    'max_rounds': maxRounds,
  };

  factory GameRules.fromJson(Map<String, dynamic> json) => GameRules(
    scoringSystem: ScoringSystem.values[json['scoring_system'] as int? ?? 0],
    roundSequence: RoundSequence.values[json['round_sequence'] as int? ?? 0],
    customRounds: (json['custom_rounds'] as List?)?.cast<int>(),
    trumpDetermination: TrumpDetermination.values[json['trump_determination'] as int? ?? 0],
    screwTheDealer: json['screw_the_dealer'] as bool? ?? true,
    allowZeroBid: json['allow_zero_bid'] as bool? ?? true,
    zeroBidBonus: json['zero_bid_bonus'] as int? ?? 0,
    maxCardsPerRound: json['max_cards_per_round'] as int?,
    maxRounds: json['max_rounds'] as int?,
  );

  /// Maak een kopie met aangepaste waarden
  GameRules copyWith({
    ScoringSystem? scoringSystem,
    RoundSequence? roundSequence,
    List<int>? customRounds,
    TrumpDetermination? trumpDetermination,
    bool? screwTheDealer,
    bool? allowZeroBid,
    int? zeroBidBonus,
    int? maxCardsPerRound,
    int? maxRounds,
  }) {
    return GameRules(
      scoringSystem: scoringSystem ?? this.scoringSystem,
      roundSequence: roundSequence ?? this.roundSequence,
      customRounds: customRounds ?? this.customRounds,
      trumpDetermination: trumpDetermination ?? this.trumpDetermination,
      screwTheDealer: screwTheDealer ?? this.screwTheDealer,
      allowZeroBid: allowZeroBid ?? this.allowZeroBid,
      zeroBidBonus: zeroBidBonus ?? this.zeroBidBonus,
      maxCardsPerRound: maxCardsPerRound ?? this.maxCardsPerRound,
      maxRounds: maxRounds ?? this.maxRounds,
    );
  }
}
