// Boerenbridge Game State Machine
// Beheert de volledige spelstroom: lobby → bieden → spelen → scores

import 'dart:math';
import 'models.dart';
import 'rules.dart';

// =============================================================================
// GAME PHASE
// =============================================================================

enum GamePhase {
  /// Wachten op spelers
  lobby,
  
  /// Kaarten zijn gedeeld, spelers bieden
  bidding,
  
  /// Slagen worden gespeeld
  playing,
  
  /// Ronde is klaar, scores worden getoond
  roundEnd,
  
  /// Spel is afgelopen
  gameEnd,
}

// =============================================================================
// GAME STATE
// =============================================================================

class GameState {
  final String gameId;
  final GameRules rules;
  final List<Player> players;
  final List<int> rounds;
  
  GamePhase phase;
  int currentRoundIndex;
  int dealerIndex;
  int currentPlayerIndex;
  Suit? trump;
  Trick? currentTrick;
  Trick? completedTrick; // Laatste voltooide slag (voor weergave)
  String? completedTrickWinnerId; // Winnaar van de laatste slag
  List<Map<String, int>> roundScores; // Historie van scores per ronde
  
  final Deck _deck = Deck();
  
  GameState({
    required this.gameId,
    required this.rules,
    required this.players,
  }) : rounds = rules.getRounds(players.length),
       phase = GamePhase.lobby,
       currentRoundIndex = 0,
       dealerIndex = 0,
       currentPlayerIndex = 0,
       completedTrick = null,
       completedTrickWinnerId = null,
       roundScores = [];
  
  // ===========================================================================
  // GETTERS
  // ===========================================================================
  
  int get cardsThisRound => rounds[currentRoundIndex];
  
  Player get currentPlayer => players[currentPlayerIndex];
  
  Player get dealer => players[dealerIndex];
  
  bool get isLastRound => currentRoundIndex >= rounds.length - 1;
  
  int get totalBidsSoFar => players
      .where((p) => p.bid != null)
      .fold(0, (sum, p) => sum + p.bid!);
  
  bool get allPlayersBid => players.every((p) => p.bid != null);
  
  /// Is de huidige speler de deler (laatste bieder)?
  bool get isCurrentPlayerDealer => currentPlayerIndex == dealerIndex;

  /// Verschil tussen totaal geboden en beschikbare slagen
  /// Positief = overgeboden, Negatief = ondergeboden, 0 = exact
  int get bidDifference => totalBidsSoFar - cardsThisRound;

  /// Tekst voor over/onderbod status
  String get bidStatusText {
    if (!allPlayersBid) return '';
    final diff = bidDifference;
    if (diff > 0) return 'Overgeboden (+$diff)';
    if (diff < 0) return 'Ondergeboden ($diff)';
    return 'Exact geboden!';
  }
  
  /// Toegestane biedingen voor de huidige speler
  List<int> get allowedBids {
    final allBids = <int>[
      if (rules.allowZeroBid) 0,
      for (var i = 1; i <= cardsThisRound; i++) i,
    ];
    
    // Alleen deler heeft restrictie bij "screw the dealer"
    if (!isCurrentPlayerDealer || !rules.screwTheDealer) {
      return allBids;
    }
    
    return rules.allowedBidsForDealer(cardsThisRound, totalBidsSoFar);
  }
  
  // ===========================================================================
  // GAME FLOW
  // ===========================================================================
  
  /// Start het spel (vanuit lobby)
  void startGame() {
    if (phase != GamePhase.lobby) {
      throw StateError('Kan spel alleen starten vanuit lobby');
    }
    if (players.length < 2) {
      throw StateError('Minimaal 2 spelers nodig');
    }
    
    // Willekeurige eerste deler
    dealerIndex = Random().nextInt(players.length);
    _startNewRound();
  }
  
  /// Start een nieuwe ronde
  void _startNewRound() {
    print('DEBUG _startNewRound: Starting round ${currentRoundIndex + 1}, cardsThisRound=$cardsThisRound');

    // Reset voltooide slag
    completedTrick = null;
    completedTrickWinnerId = null;

    // Reset spelers voor nieuwe ronde
    for (final player in players) {
      player.hand.clear();
      player.bid = null;
      player.tricksTaken = 0;
    }

    // Schud en deel
    _deck.reset();
    _deck.shuffle();

    print('DEBUG _startNewRound: Deck has ${_deck.remaining} cards, dealing $cardsThisRound to ${players.length} players');

    for (final player in players) {
      player.hand.addAll(_deck.deal(cardsThisRound));
      // Sorteer hand voor UX
      player.hand.sort((a, b) {
        final suitCompare = a.suit.index.compareTo(b.suit.index);
        if (suitCompare != 0) return suitCompare;
        return a.rank.value.compareTo(b.rank.value);
      });
      print('DEBUG _startNewRound: ${player.name} now has ${player.hand.length} cards: ${player.hand}');
    }

    // Bepaal troef
    trump = _determineTrump();

    // Eerste bieder is links van de deler
    currentPlayerIndex = (dealerIndex + 1) % players.length;
    phase = GamePhase.bidding;

    print('DEBUG _startNewRound: Done. Phase=$phase, trump=$trump');
  }
  
  Suit? _determineTrump() {
    return switch (rules.trumpDetermination) {
      TrumpDetermination.topCard => _deck.remaining > 0 
          ? _deck.deal(1).first.suit 
          : null,
      TrumpDetermination.rotating => 
          Suit.values[currentRoundIndex % 5 < 4 ? currentRoundIndex % 5 : -1],
      TrumpDetermination.noTrump => null,
      TrumpDetermination.dealerChoice => null, // Wordt later gezet
    };
  }
  
  /// Speler plaatst een bod
  void placeBid(String playerId, int bid) {
    if (phase != GamePhase.bidding) {
      throw StateError('Niet in bied-fase');
    }
    
    final player = players.firstWhere((p) => p.id == playerId);
    if (player.id != currentPlayer.id) {
      throw StateError('Niet aan de beurt');
    }
    
    if (!allowedBids.contains(bid)) {
      throw StateError('Ongeldige bieding: $bid');
    }
    
    player.bid = bid;
    
    // Volgende speler of start met spelen
    if (allPlayersBid) {
      _startPlaying();
    } else {
      currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    }
  }
  
  void _startPlaying() {
    phase = GamePhase.playing;
    currentTrick = Trick(trump: trump);
    // Eerste speler van eerste slag is links van deler
    currentPlayerIndex = (dealerIndex + 1) % players.length;
  }
  
  /// Speler speelt een kaart
  void playCard(String playerId, Card card) {
    if (phase != GamePhase.playing) {
      throw StateError('Niet in speel-fase');
    }

    final player = players.firstWhere((p) => p.id == playerId);
    if (player.id != currentPlayer.id) {
      throw StateError('Niet aan de beurt');
    }

    if (!player.hand.contains(card)) {
      throw StateError('Kaart niet in hand');
    }

    if (!player.canPlay(card, currentTrick?.leadSuit)) {
      throw StateError('Je moet bekennen!');
    }

    // Wis de voltooide slag als we een nieuwe slag beginnen
    if (currentTrick?.cards.isEmpty ?? true) {
      completedTrick = null;
      completedTrickWinnerId = null;
    }

    // Speel de kaart
    player.playCard(card);
    currentTrick!.addCard(playerId, card);

    // Slag compleet?
    if (currentTrick!.cards.length == players.length) {
      _completeTrick();
    } else {
      currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    }
  }
  
  void _completeTrick() {
    final winnerId = currentTrick!.winnerId!;
    final winner = players.firstWhere((p) => p.id == winnerId);
    winner.tricksTaken++;

    // Bewaar de voltooide slag voor weergave
    completedTrick = currentTrick;
    completedTrickWinnerId = winnerId;

    // Alle slagen gespeeld?
    if (players.first.hand.isEmpty) {
      _completeRound();
    } else {
      // Winnaar begint volgende slag
      currentPlayerIndex = players.indexWhere((p) => p.id == winnerId);
      currentTrick = Trick(trump: trump);
    }
  }
  
  void _completeRound() {
    // Bereken scores
    final scores = <String, int>{};
    for (final player in players) {
      final score = rules.calculateRoundScore(player.bid!, player.tricksTaken);
      player.totalScore += score;
      scores[player.id] = score;
    }
    roundScores.add(scores);
    
    phase = GamePhase.roundEnd;
  }
  
  /// Ga naar volgende ronde of eindig spel
  void nextRound() {
    print('DEBUG nextRound: Called. phase=$phase, currentRoundIndex=$currentRoundIndex, isLastRound=$isLastRound');
    if (phase != GamePhase.roundEnd) {
      throw StateError('Niet in ronde-eind fase');
    }

    if (isLastRound) {
      print('DEBUG nextRound: Last round, ending game');
      phase = GamePhase.gameEnd;
    } else {
      currentRoundIndex++;
      dealerIndex = (dealerIndex + 1) % players.length;
      print('DEBUG nextRound: Moving to round ${currentRoundIndex + 1}, new dealerIndex=$dealerIndex');
      _startNewRound();
    }
  }
  
  // ===========================================================================
  // SERIALIZATION (voor Supabase sync)
  // ===========================================================================
  
  Map<String, dynamic> toJson() => {
    'game_id': gameId,
    'rules': rules.toJson(),
    'players': players.map((p) => p.toJson()).toList(),
    'phase': phase.index,
    'current_round_index': currentRoundIndex,
    'dealer_index': dealerIndex,
    'current_player_index': currentPlayerIndex,
    'trump': trump?.index,
    'current_trick': currentTrick?.toJson(),
    'completed_trick': completedTrick?.toJson(),
    'completed_trick_winner_id': completedTrickWinnerId,
    'round_scores': roundScores,
  };
  
  factory GameState.fromJson(Map<String, dynamic> json) {
    final state = GameState(
      gameId: json['game_id'] as String,
      rules: GameRules.fromJson(json['rules'] as Map<String, dynamic>),
      players: (json['players'] as List)
          .map((p) => Player.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
    
    state.phase = GamePhase.values[json['phase'] as int];
    state.currentRoundIndex = json['current_round_index'] as int;
    state.dealerIndex = json['dealer_index'] as int;
    state.currentPlayerIndex = json['current_player_index'] as int;
    state.trump = json['trump'] != null
        ? Suit.values[json['trump'] as int]
        : null;
    state.currentTrick = json['current_trick'] != null
        ? Trick.fromJson(json['current_trick'] as Map<String, dynamic>)
        : null;
    state.completedTrick = json['completed_trick'] != null
        ? Trick.fromJson(json['completed_trick'] as Map<String, dynamic>)
        : null;
    state.completedTrickWinnerId = json['completed_trick_winner_id'] as String?;
    state.roundScores = (json['round_scores'] as List?)
        ?.map((r) => Map<String, int>.from(r as Map))
        .toList() ?? [];

    return state;
  }
  
  /// Maak een "view" van de state voor een specifieke speler
  /// (verbergt kaarten van andere spelers)
  Map<String, dynamic> toPlayerView(String playerId) {
    final json = toJson();
    
    // Verberg kaarten van andere spelers
    final playersView = (json['players'] as List).map((p) {
      final playerMap = Map<String, dynamic>.from(p as Map);
      if (playerMap['id'] != playerId) {
        // Vervang kaarten door alleen het aantal
        playerMap['hand'] = List.filled(
          (playerMap['hand'] as List).length, 
          null,
        );
      }
      return playerMap;
    }).toList();
    
    json['players'] = playersView;
    return json;
  }
}
