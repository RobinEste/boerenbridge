import 'package:flutter_test/flutter_test.dart';
import 'package:boerenbridge/game/game_state.dart';
import 'package:boerenbridge/game/models.dart';
import 'package:boerenbridge/game/rules.dart';

void main() {
  group('GameState', () {
    late GameState gameState;
    late List<Player> players;

    setUp(() {
      players = [
        Player(id: 'p1', odataId: 'auth1', name: 'Alice'),
        Player(id: 'p2', odataId: 'auth2', name: 'Bob'),
        Player(id: 'p3', odataId: 'auth3', name: 'Charlie'),
      ];

      gameState = GameState(
        gameId: 'game-123',
        rules: const GameRules(maxRounds: 5),
        players: players,
      );
    });

    group('initialization', () {
      test('starts in lobby phase', () {
        expect(gameState.phase, equals(GamePhase.lobby));
      });

      test('has correct number of rounds', () {
        expect(gameState.rounds.length, equals(5));
        expect(gameState.rounds, equals([1, 2, 3, 4, 5]));
      });

      test('starts at round 0', () {
        expect(gameState.currentRoundIndex, equals(0));
      });
    });

    group('startGame', () {
      test('transitions to bidding phase', () {
        gameState.startGame();
        expect(gameState.phase, equals(GamePhase.bidding));
      });

      test('deals cards to all players', () {
        gameState.startGame();

        for (final player in gameState.players) {
          expect(player.hand.length, equals(gameState.cardsThisRound));
        }
      });

      test('sets trump', () {
        gameState.startGame();
        // Trump might be null depending on determination method,
        // but the field should be set
        expect(gameState.trump, isNotNull);
      });

      test('throws when not in lobby', () {
        gameState.startGame();
        expect(() => gameState.startGame(), throwsStateError);
      });

      test('throws with less than 2 players', () {
        final singlePlayer = GameState(
          gameId: 'game-123',
          rules: GameRules.dutch,
          players: [Player(id: 'p1', name: 'Alice')],
        );

        expect(() => singlePlayer.startGame(), throwsStateError);
      });
    });

    group('placeBid', () {
      setUp(() {
        gameState.startGame();
      });

      test('records bid for current player', () {
        final currentPlayerId = gameState.currentPlayer.id;
        gameState.placeBid(currentPlayerId, 1);

        final player = gameState.players.firstWhere((p) => p.id == currentPlayerId);
        expect(player.bid, equals(1));
      });

      test('advances to next player', () {
        final firstPlayerId = gameState.currentPlayer.id;
        gameState.placeBid(firstPlayerId, 0);

        expect(gameState.currentPlayer.id, isNot(equals(firstPlayerId)));
      });

      test('transitions to playing when all have bid', () {
        // All players bid
        for (var i = 0; i < players.length; i++) {
          gameState.placeBid(gameState.currentPlayer.id, 0);
        }

        expect(gameState.phase, equals(GamePhase.playing));
      });

      test('throws when not current player', () {
        final wrongPlayerId = gameState.players
            .firstWhere((p) => p.id != gameState.currentPlayer.id)
            .id;

        expect(
          () => gameState.placeBid(wrongPlayerId, 0),
          throwsStateError,
        );
      });

      test('throws for invalid bid', () {
        expect(
          () => gameState.placeBid(gameState.currentPlayer.id, 999),
          throwsStateError,
        );
      });

      test('throws when not in bidding phase', () {
        // Complete bidding
        for (var i = 0; i < players.length; i++) {
          gameState.placeBid(gameState.currentPlayer.id, 0);
        }

        expect(
          () => gameState.placeBid(gameState.currentPlayer.id, 0),
          throwsStateError,
        );
      });
    });

    group('allowedBids', () {
      setUp(() {
        gameState.startGame();
      });

      test('includes valid range', () {
        final bids = gameState.allowedBids;

        expect(bids, contains(0));
        expect(bids, contains(1)); // cardsThisRound in round 1
      });

      test('dealer cannot bid exact difference with screw the dealer', () {
        // Make first two players bid
        gameState.placeBid(gameState.currentPlayer.id, 0);
        gameState.placeBid(gameState.currentPlayer.id, 0);

        // Third player (dealer) cannot bid 1 (1 - 0 = 1)
        expect(gameState.isCurrentPlayerDealer, isTrue);
        expect(gameState.allowedBids, isNot(contains(1)));
      });
    });

    group('playCard', () {
      setUp(() {
        gameState.startGame();
        // All players bid 0
        for (var i = 0; i < players.length; i++) {
          gameState.placeBid(gameState.currentPlayer.id, 0);
        }
      });

      test('removes card from player hand', () {
        final player = gameState.currentPlayer;
        final card = player.hand.first;
        final handSizeBefore = player.hand.length;

        gameState.playCard(player.id, card);

        expect(player.hand.length, equals(handSizeBefore - 1));
        expect(player.hand, isNot(contains(card)));
      });

      test('adds card to current trick', () {
        final player = gameState.currentPlayer;
        final card = player.hand.first;

        gameState.playCard(player.id, card);

        expect(gameState.currentTrick!.cards.length, equals(1));
        expect(gameState.currentTrick!.cards.first.card, equals(card));
      });

      test('completes trick when all players have played', () {
        // All players play a card
        for (var i = 0; i < players.length; i++) {
          final player = gameState.currentPlayer;
          final card = player.hand.first;
          gameState.playCard(player.id, card);
        }

        // Trick should be completed and stored
        expect(gameState.completedTrick, isNotNull);
      });

      test('winner gets trick counted', () {
        // Play all cards
        for (var i = 0; i < players.length; i++) {
          final player = gameState.currentPlayer;
          final card = player.hand.first;
          gameState.playCard(player.id, card);
        }

        // One player should have tricksTaken = 1
        final totalTricks = gameState.players.fold<int>(
          0,
          (sum, p) => sum + p.tricksTaken,
        );
        expect(totalTricks, equals(1));
      });

      test('throws when not current player', () {
        final wrongPlayer = gameState.players
            .firstWhere((p) => p.id != gameState.currentPlayer.id);
        final card = wrongPlayer.hand.first;

        expect(
          () => gameState.playCard(wrongPlayer.id, card),
          throwsStateError,
        );
      });

      test('throws when card not in hand', () {
        const fakeCard = Card(Suit.hearts, Rank.ace);

        expect(
          () => gameState.playCard(gameState.currentPlayer.id, fakeCard),
          throwsStateError,
        );
      });
    });

    group('nextRound', () {
      setUp(() {
        gameState.startGame();
        // Complete a full round
        for (var i = 0; i < players.length; i++) {
          gameState.placeBid(gameState.currentPlayer.id, 0);
        }
        // Play all tricks (1 card each in round 1)
        for (var i = 0; i < players.length; i++) {
          final player = gameState.currentPlayer;
          gameState.playCard(player.id, player.hand.first);
        }
      });

      test('advances to next round', () {
        expect(gameState.phase, equals(GamePhase.roundEnd));

        gameState.nextRound();

        expect(gameState.currentRoundIndex, equals(1));
        expect(gameState.phase, equals(GamePhase.bidding));
      });

      test('deals new cards', () {
        gameState.nextRound();

        // Round 2 has 2 cards
        for (final player in gameState.players) {
          expect(player.hand.length, equals(2));
        }
      });

      test('resets player state', () {
        gameState.nextRound();

        for (final player in gameState.players) {
          expect(player.bid, isNull);
          expect(player.tricksTaken, equals(0));
        }
      });

      test('transitions to gameEnd on last round', () {
        // Create fresh game state for this test
        final testPlayers = [
          Player(id: 'p1', odataId: 'auth1', name: 'Alice'),
          Player(id: 'p2', odataId: 'auth2', name: 'Bob'),
          Player(id: 'p3', odataId: 'auth3', name: 'Charlie'),
        ];
        final testGame = GameState(
          gameId: 'test-game-end',
          rules: const GameRules(maxRounds: 3), // Shorter for faster test
          players: testPlayers,
        );
        testGame.startGame();

        // Play through all 3 rounds
        for (var round = 0; round < 3; round++) {
          // Bid - use allowedBids to handle screw the dealer
          while (!testGame.allPlayersBid) {
            final bid = testGame.allowedBids.contains(0) ? 0 : testGame.allowedBids.first;
            testGame.placeBid(testGame.currentPlayer.id, bid);
          }

          // Play all tricks - use playableCards to respect follow suit rule
          while (testGame.phase == GamePhase.playing) {
            final player = testGame.currentPlayer;
            final leadSuit = testGame.currentTrick?.leadSuit;
            final playableCards = player.playableCards(leadSuit);
            testGame.playCard(player.id, playableCards.first);
          }

          if (round < 2) {
            testGame.nextRound();
          }
        }

        expect(testGame.phase, equals(GamePhase.roundEnd));
        testGame.nextRound();
        expect(testGame.phase, equals(GamePhase.gameEnd));
      });
    });

    group('bidStatusText', () {
      setUp(() {
        gameState.startGame();
      });

      test('shows overbid when total > cards', () {
        // In round 1 with 1 card, if everyone bids 1, total = 3
        for (var i = 0; i < players.length; i++) {
          final allowed = gameState.allowedBids;
          // Pick highest allowed bid
          final bid = allowed.where((b) => b > 0).isNotEmpty
              ? allowed.where((b) => b > 0).first
              : 0;
          gameState.placeBid(gameState.currentPlayer.id, bid);
        }

        expect(gameState.bidStatusText, contains('Overgeboden'));
      });

      test('shows underbid when total < cards', () {
        // All bid 0 means underbid
        for (var i = 0; i < players.length; i++) {
          gameState.placeBid(gameState.currentPlayer.id, 0);
        }

        expect(gameState.bidStatusText, contains('Ondergeboden'));
      });
    });

    group('serialization', () {
      test('toJson includes all fields', () {
        gameState.startGame();
        final json = gameState.toJson();

        expect(json['game_id'], equals('game-123'));
        expect(json['rules'], isNotNull);
        expect(json['players'], hasLength(3));
        expect(json['phase'], equals(GamePhase.bidding.index));
        expect(json['current_round_index'], equals(0));
        expect(json['trump'], isNotNull);
      });

      test('fromJson restores game state', () {
        gameState.startGame();
        // Place some bids
        gameState.placeBid(gameState.currentPlayer.id, 0);

        final json = gameState.toJson();
        final restored = GameState.fromJson(json);

        expect(restored.gameId, equals(gameState.gameId));
        expect(restored.phase, equals(gameState.phase));
        expect(restored.currentRoundIndex, equals(gameState.currentRoundIndex));
        expect(restored.players.length, equals(gameState.players.length));
        expect(restored.trump, equals(gameState.trump));
      });

      test('roundtrip preserves current trick', () {
        gameState.startGame();
        // All bid
        for (var i = 0; i < players.length; i++) {
          gameState.placeBid(gameState.currentPlayer.id, 0);
        }
        // Play one card
        final player = gameState.currentPlayer;
        gameState.playCard(player.id, player.hand.first);

        final json = gameState.toJson();
        final restored = GameState.fromJson(json);

        expect(restored.currentTrick, isNotNull);
        expect(restored.currentTrick!.cards.length, equals(1));
      });

      test('roundtrip preserves completed trick', () {
        gameState.startGame();
        // All bid
        for (var i = 0; i < players.length; i++) {
          gameState.placeBid(gameState.currentPlayer.id, 0);
        }
        // All play cards to complete trick
        for (var i = 0; i < players.length; i++) {
          final player = gameState.currentPlayer;
          gameState.playCard(player.id, player.hand.first);
        }

        final json = gameState.toJson();
        final restored = GameState.fromJson(json);

        expect(restored.completedTrick, isNotNull);
        expect(restored.completedTrickWinnerId, isNotNull);
      });

      test('roundtrip preserves player hands', () {
        gameState.startGame();

        final originalHands = gameState.players
            .map((p) => p.hand.map((c) => c.toString()).toList())
            .toList();

        final json = gameState.toJson();
        final restored = GameState.fromJson(json);

        for (var i = 0; i < players.length; i++) {
          final restoredHand =
              restored.players[i].hand.map((c) => c.toString()).toList();
          expect(restoredHand, equals(originalHands[i]));
        }
      });

      test('roundtrip preserves player odataId', () {
        gameState.startGame();

        final json = gameState.toJson();
        final restored = GameState.fromJson(json);

        for (var i = 0; i < players.length; i++) {
          expect(
            restored.players[i].odataId,
            equals(gameState.players[i].odataId),
          );
        }
      });
    });

    group('toPlayerView', () {
      test('hides other players cards', () {
        gameState.startGame();

        final view = gameState.toPlayerView('p1');
        final playersView = view['players'] as List;

        // Player 1 should see their cards
        final p1Cards = (playersView[0]['hand'] as List);
        expect(p1Cards.every((c) => c != null), isTrue);

        // Other players cards should be null
        final p2Cards = (playersView[1]['hand'] as List);
        expect(p2Cards.every((c) => c == null), isTrue);
      });

      test('preserves card count', () {
        gameState.startGame();

        final view = gameState.toPlayerView('p1');
        final playersView = view['players'] as List;

        // All players should show same hand size
        for (final playerView in playersView) {
          expect(
            (playerView['hand'] as List).length,
            equals(gameState.cardsThisRound),
          );
        }
      });
    });
  });
}
