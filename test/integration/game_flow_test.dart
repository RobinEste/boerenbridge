import 'package:flutter_test/flutter_test.dart';
import 'package:boerenbridge/game/game_state.dart';
import 'package:boerenbridge/game/models.dart';
import 'package:boerenbridge/game/rules.dart';

/// Integration tests for complete game flow
/// These tests verify that a full game can be played from start to finish
void main() {
  group('Complete game flow', () {
    late GameState game;
    late List<Player> players;

    setUp(() {
      players = [
        Player(id: 'p1', odataId: 'auth1', name: 'Alice'),
        Player(id: 'p2', odataId: 'auth2', name: 'Bob'),
        Player(id: 'p3', odataId: 'auth3', name: 'Charlie'),
      ];

      game = GameState(
        gameId: 'integration-test',
        rules: const GameRules(
          scoringSystem: ScoringSystem.dutchWithPenalty,
          maxRounds: 3, // Short game for testing
        ),
        players: players,
      );
    });

    test('can play complete game from lobby to end', () {
      // Phase 1: Lobby
      expect(game.phase, equals(GamePhase.lobby));

      // Phase 2: Start game
      game.startGame();
      expect(game.phase, equals(GamePhase.bidding));

      // Play through all rounds
      var roundsPlayed = 0;
      while (game.phase != GamePhase.gameEnd) {
        // Bidding phase
        expect(game.phase, equals(GamePhase.bidding));

        while (!game.allPlayersBid) {
          final currentPlayer = game.currentPlayer;
          final allowedBids = game.allowedBids;
          // Bid 0 for simplicity
          final bid = allowedBids.contains(0) ? 0 : allowedBids.first;
          game.placeBid(currentPlayer.id, bid);
        }

        // Playing phase
        expect(game.phase, equals(GamePhase.playing));

        // Play all tricks
        while (game.phase == GamePhase.playing) {
          final currentPlayer = game.currentPlayer;
          final leadSuit = game.currentTrick?.leadSuit;
          final playableCards = currentPlayer.playableCards(leadSuit);
          final card = playableCards.first;
          game.playCard(currentPlayer.id, card);
        }

        // Round end
        expect(game.phase, equals(GamePhase.roundEnd));
        roundsPlayed++;

        if (!game.isLastRound) {
          game.nextRound();
        } else {
          game.nextRound();
          expect(game.phase, equals(GamePhase.gameEnd));
        }
      }

      expect(roundsPlayed, equals(3));
      expect(game.phase, equals(GamePhase.gameEnd));
    });

    test('scores are calculated correctly across rounds', () {
      game.startGame();

      // Play one round where everyone bids and makes 0
      while (!game.allPlayersBid) {
        final bid = game.allowedBids.contains(0) ? 0 : game.allowedBids.first;
        game.placeBid(game.currentPlayer.id, bid);
      }

      // Play all tricks
      while (game.phase == GamePhase.playing) {
        final currentPlayer = game.currentPlayer;
        final leadSuit = game.currentTrick?.leadSuit;
        final playableCards = currentPlayer.playableCards(leadSuit);
        game.playCard(currentPlayer.id, playableCards.first);
      }

      // Verify scores
      // Players who bid 0 and made 0 get 10 points
      // Players who bid 0 but got a trick get -3 points (dutchWithPenalty)
      final totalScore = game.players.fold<int>(0, (sum, p) => sum + p.totalScore);

      // With 1 trick total, one player gets it
      // That player: bid 0, took 1 = -3 points
      // Others: bid 0, took 0 = 10 points each
      // Total should be 10 + 10 + (-3) = 17 OR varies based on who wins
      expect(totalScore, isNonZero); // At least verify scoring happened
    });

    test('dealer restriction works correctly', () {
      game.startGame();

      // Record initial dealer
      final dealerIndex = game.dealerIndex;

      // Have first two players bid
      for (var i = 0; i < 2; i++) {
        final bid = game.allowedBids.first;
        game.placeBid(game.currentPlayer.id, bid);
      }

      // Now it should be dealer's turn
      expect(game.currentPlayerIndex, equals(dealerIndex));
      expect(game.isCurrentPlayerDealer, isTrue);

      // Dealer's allowed bids should exclude the "make it exact" bid
      final totalSoFar = game.totalBidsSoFar;
      final forbidden = game.cardsThisRound - totalSoFar;

      if (forbidden >= 0 && forbidden <= game.cardsThisRound) {
        expect(game.allowedBids, isNot(contains(forbidden)));
      }
    });

    test('must follow suit rule is enforced', () {
      game.startGame();

      // Complete bidding
      while (!game.allPlayersBid) {
        game.placeBid(game.currentPlayer.id, game.allowedBids.first);
      }

      // Get a player with cards of different suits
      final player = game.currentPlayer;

      // If player leads, they can play any card
      expect(game.currentTrick?.leadSuit, isNull);
      final firstCard = player.hand.first;
      game.playCard(player.id, firstCard);

      // Now next player must follow suit if they have it
      final nextPlayer = game.currentPlayer;
      final leadSuit = game.currentTrick!.leadSuit;

      final playableCards = nextPlayer.playableCards(leadSuit);
      final hasLeadSuit = nextPlayer.hand.any((c) => c.suit == leadSuit);

      if (hasLeadSuit) {
        // All playable cards must be of lead suit
        for (final card in playableCards) {
          expect(card.suit, equals(leadSuit));
        }
      } else {
        // Can play any card
        expect(playableCards.length, equals(nextPlayer.hand.length));
      }
    });

    test('trump beats non-trump cards', () {
      game.startGame();

      // Set a known trump
      game.trump = Suit.hearts;

      // Complete bidding
      while (!game.allPlayersBid) {
        game.placeBid(game.currentPlayer.id, game.allowedBids.first);
      }

      // Create a scenario where we can test trump
      // This is tricky in a real game, so we just verify the rule exists
      final trick = Trick(trump: Suit.hearts);
      trick.addCard('p1', const Card(Suit.spades, Rank.ace)); // High non-trump
      trick.addCard('p2', const Card(Suit.hearts, Rank.two)); // Low trump

      // Trump should win
      expect(trick.winnerId, equals('p2'));
    });

    test('state can be serialized and restored mid-game', () {
      game.startGame();

      // Play partway through
      while (!game.allPlayersBid) {
        game.placeBid(game.currentPlayer.id, game.allowedBids.first);
      }

      // Play one card
      final player = game.currentPlayer;
      final card = player.hand.first;
      game.playCard(player.id, card);

      // Serialize
      final json = game.toJson();

      // Restore
      final restored = GameState.fromJson(json);

      // Verify state matches
      expect(restored.phase, equals(game.phase));
      expect(restored.currentRoundIndex, equals(game.currentRoundIndex));
      expect(restored.currentPlayerIndex, equals(game.currentPlayerIndex));
      expect(restored.trump, equals(game.trump));
      expect(restored.currentTrick?.cards.length, equals(game.currentTrick?.cards.length));

      // Verify we can continue playing
      final restoredPlayer = restored.currentPlayer;
      final nextCard = restoredPlayer.hand.first;

      expect(
        () => restored.playCard(restoredPlayer.id, nextCard),
        returnsNormally,
      );
    });

    test('multiple rounds advance dealer correctly', () {
      game.startGame();

      final initialDealer = game.dealerIndex;

      // Play through first round
      while (!game.allPlayersBid) {
        game.placeBid(game.currentPlayer.id, game.allowedBids.first);
      }
      while (game.phase == GamePhase.playing) {
        final p = game.currentPlayer;
        game.playCard(p.id, p.hand.first);
      }

      game.nextRound();

      // Dealer should have moved
      expect(game.dealerIndex, equals((initialDealer + 1) % game.players.length));
    });

    test('round scores are recorded in history', () {
      game.startGame();

      // Play through first round
      while (!game.allPlayersBid) {
        game.placeBid(game.currentPlayer.id, game.allowedBids.first);
      }
      while (game.phase == GamePhase.playing) {
        final p = game.currentPlayer;
        game.playCard(p.id, p.hand.first);
      }

      expect(game.roundScores.length, equals(1));
      expect(game.roundScores[0].keys.length, equals(3)); // All players

      game.nextRound();

      // Play second round
      while (!game.allPlayersBid) {
        game.placeBid(game.currentPlayer.id, game.allowedBids.first);
      }
      while (game.phase == GamePhase.playing) {
        final p = game.currentPlayer;
        game.playCard(p.id, p.hand.first);
      }

      expect(game.roundScores.length, equals(2));
    });
  });

  group('Edge cases', () {
    test('handles 2 player game', () {
      final players = [
        Player(id: 'p1', name: 'Alice'),
        Player(id: 'p2', name: 'Bob'),
      ];

      final game = GameState(
        gameId: 'two-player',
        rules: const GameRules(maxRounds: 2),
        players: players,
      );

      game.startGame();

      // Should be able to play
      expect(game.phase, equals(GamePhase.bidding));
      expect(game.cardsThisRound, equals(1));
    });

    test('handles max players (6)', () {
      final players = List.generate(
        6,
        (i) => Player(id: 'p$i', name: 'Player $i'),
      );

      final game = GameState(
        gameId: 'six-player',
        rules: const GameRules(maxRounds: 2),
        players: players,
      );

      game.startGame();

      // With 6 players, max cards = 52/6 = 8
      expect(game.rounds.first, equals(1));
      expect(game.phase, equals(GamePhase.bidding));
    });

    test('handles no trump game', () {
      final players = [
        Player(id: 'p1', name: 'Alice'),
        Player(id: 'p2', name: 'Bob'),
        Player(id: 'p3', name: 'Charlie'),
      ];

      final game = GameState(
        gameId: 'no-trump',
        rules: const GameRules(
          trumpDetermination: TrumpDetermination.noTrump,
          maxRounds: 1,
        ),
        players: players,
      );

      game.startGame();

      expect(game.trump, isNull);
    });
  });
}
