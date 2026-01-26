/// Test helpers and utilities for Boerenbridge tests

import 'package:boerenbridge/game/game_state.dart';
import 'package:boerenbridge/game/models.dart';
import 'package:boerenbridge/game/rules.dart';

/// Creates a list of test players
List<Player> createTestPlayers({
  int count = 3,
  bool withAuthIds = true,
}) {
  return List.generate(count, (i) {
    return Player(
      id: 'player-$i',
      odataId: withAuthIds ? 'auth-$i' : null,
      name: 'Player ${i + 1}',
    );
  });
}

/// Creates a game state in a specific phase for testing
GameState createGameStateInPhase({
  GamePhase phase = GamePhase.lobby,
  int playerCount = 3,
  int maxRounds = 3,
  ScoringSystem scoringSystem = ScoringSystem.basis,
}) {
  final players = createTestPlayers(count: playerCount);
  final game = GameState(
    gameId: 'test-game-${DateTime.now().millisecondsSinceEpoch}',
    rules: GameRules(
      scoringSystem: scoringSystem,
      maxRounds: maxRounds,
    ),
    players: players,
  );

  if (phase == GamePhase.lobby) {
    return game;
  }

  game.startGame();

  if (phase == GamePhase.bidding) {
    return game;
  }

  // Complete bidding
  for (var i = 0; i < playerCount; i++) {
    final bid = game.allowedBids.contains(0) ? 0 : game.allowedBids.first;
    game.placeBid(game.currentPlayer.id, bid);
  }

  if (phase == GamePhase.playing) {
    return game;
  }

  // Complete all tricks
  while (game.phase == GamePhase.playing) {
    final player = game.currentPlayer;
    game.playCard(player.id, player.hand.first);
  }

  if (phase == GamePhase.roundEnd) {
    return game;
  }

  // Advance to game end
  while (game.phase != GamePhase.gameEnd) {
    if (game.phase == GamePhase.roundEnd) {
      game.nextRound();
    }
    if (game.phase == GamePhase.bidding) {
      for (var i = 0; i < playerCount; i++) {
        final bid = game.allowedBids.contains(0) ? 0 : game.allowedBids.first;
        game.placeBid(game.currentPlayer.id, bid);
      }
    }
    if (game.phase == GamePhase.playing) {
      while (game.phase == GamePhase.playing) {
        final player = game.currentPlayer;
        game.playCard(player.id, player.hand.first);
      }
    }
  }

  return game;
}

/// Creates a specific card for testing
Card testCard(String notation) {
  // Parse notation like "AH" (Ace of Hearts) or "2S" (2 of Spades)
  final rankChar = notation.substring(0, notation.length - 1);
  final suitChar = notation.substring(notation.length - 1);

  final rank = switch (rankChar) {
    '2' => Rank.two,
    '3' => Rank.three,
    '4' => Rank.four,
    '5' => Rank.five,
    '6' => Rank.six,
    '7' => Rank.seven,
    '8' => Rank.eight,
    '9' => Rank.nine,
    '10' => Rank.ten,
    'J' || 'B' => Rank.jack,
    'Q' || 'V' => Rank.queen,
    'K' || 'H' => Rank.king,
    'A' => Rank.ace,
    _ => throw ArgumentError('Unknown rank: $rankChar'),
  };

  final suit = switch (suitChar.toUpperCase()) {
    'H' => Suit.hearts,
    'D' => Suit.diamonds,
    'C' => Suit.clubs,
    'S' => Suit.spades,
    _ => throw ArgumentError('Unknown suit: $suitChar'),
  };

  return Card(suit, rank);
}

/// Creates a list of cards from notations
List<Card> testCards(List<String> notations) {
  return notations.map(testCard).toList();
}

/// Extension for easier testing
extension GameStateTestExtensions on GameState {
  /// Quickly complete the bidding phase with all 0 bids
  void completeBiddingWithZeros() {
    while (phase == GamePhase.bidding && !allPlayersBid) {
      final bid = allowedBids.contains(0) ? 0 : allowedBids.first;
      placeBid(currentPlayer.id, bid);
    }
  }

  /// Quickly play all remaining tricks
  void playAllTricks() {
    while (phase == GamePhase.playing) {
      final player = currentPlayer;
      playCard(player.id, player.hand.first);
    }
  }

  /// Complete current round
  void completeRound() {
    if (phase == GamePhase.bidding) {
      completeBiddingWithZeros();
    }
    if (phase == GamePhase.playing) {
      playAllTricks();
    }
  }
}
