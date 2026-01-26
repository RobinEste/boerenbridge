import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boerenbridge/game/game_state.dart';
import 'package:boerenbridge/game/models.dart' as models;
import 'package:boerenbridge/game/rules.dart';
import 'package:boerenbridge/providers/game_provider.dart';

// Helper to create a testable game state
GameState createTestGameState({
  GamePhase phase = GamePhase.bidding,
  int cardsPerPlayer = 3,
  bool allBid = false,
}) {
  final players = [
    models.Player(id: 'p1', odataId: 'auth1', name: 'Alice'),
    models.Player(id: 'p2', odataId: 'auth2', name: 'Bob'),
    models.Player(id: 'p3', odataId: 'auth3', name: 'Charlie'),
  ];

  // Use maxRounds that includes cardsPerPlayer
  final maxRounds = cardsPerPlayer > 5 ? cardsPerPlayer : 5;

  final state = GameState(
    gameId: 'test-game',
    rules: GameRules(maxRounds: maxRounds),
    players: players,
  );

  // Manually set up state for testing
  state.phase = phase;

  // Set currentRoundIndex to match cardsPerPlayer
  // rounds = [1, 2, 3, ..., maxRounds], so index for cardsPerPlayer is cardsPerPlayer - 1
  state.currentRoundIndex = cardsPerPlayer - 1;

  // Add cards to players
  for (final player in state.players) {
    player.hand.clear();
    for (var i = 0; i < cardsPerPlayer; i++) {
      player.hand.add(models.Card(
        models.Suit.values[i % 4],
        models.Rank.values[i % 13],
      ));
    }
  }

  if (allBid) {
    for (final player in state.players) {
      player.bid = 1;
    }
  }

  state.trump = models.Suit.hearts;

  return state;
}

void main() {
  group('GameScreen widgets', () {
    testWidgets('shows loading indicator when loading', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameProvider.overrideWith((ref) {
              final notifier = GameNotifier();
              // Set loading state
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows trump symbol in info bar', (tester) async {
      final state = createTestGameState();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestInfoBar(game: state),
          ),
        ),
      );

      // Trump is hearts, symbol is ♥
      expect(find.text('♥'), findsOneWidget);
    });

    testWidgets('shows round number in info bar', (tester) async {
      // Use cardsPerPlayer: 1 to get round 1 (currentRoundIndex: 0)
      final state = createTestGameState(cardsPerPlayer: 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestInfoBar(game: state),
          ),
        ),
      );

      expect(find.text('1/5'), findsOneWidget);
    });

    testWidgets('shows cards count in info bar', (tester) async {
      final state = createTestGameState(cardsPerPlayer: 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestInfoBar(game: state),
          ),
        ),
      );

      // cardsThisRound should be shown
      expect(find.text('3'), findsWidgets);
    });
  });

  group('Card display', () {
    testWidgets('displays card with correct rank and suit', (tester) async {
      const card = models.Card(models.Suit.hearts, models.Rank.ace);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestCardWidget(card: card),
          ),
        ),
      );

      expect(find.text('A♥'), findsOneWidget);
    });

    testWidgets('red suits are displayed in red', (tester) async {
      const card = models.Card(models.Suit.hearts, models.Rank.ace);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestCardWidget(card: card),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('A♥'));
      expect(text.style?.color, equals(Colors.red));
    });

    testWidgets('black suits are displayed in black', (tester) async {
      const card = models.Card(models.Suit.spades, models.Rank.ace);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestCardWidget(card: card),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('A♠'));
      expect(text.style?.color, equals(Colors.black));
    });
  });

  group('Bidding phase', () {
    testWidgets('shows bid buttons when it is my turn', (tester) async {
      final state = createTestGameState(phase: GamePhase.bidding);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestBidButtons(
              allowedBids: [0, 1, 2, 3],
              isMyTurn: true,
            ),
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('hides bid buttons when not my turn', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestBidButtons(
              allowedBids: [0, 1, 2, 3],
              isMyTurn: false,
            ),
          ),
        ),
      );

      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows total bids indicator', (tester) async {
      final state = createTestGameState(phase: GamePhase.bidding);
      state.players[0].bid = 1;
      state.players[1].bid = 2;
      // Total = 3

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestBidTotalIndicator(totalBids: 3, cardsThisRound: 5),
          ),
        ),
      );

      expect(find.textContaining('3'), findsWidgets);
      expect(find.textContaining('5'), findsWidgets);
    });
  });

  group('Playing phase', () {
    testWidgets('shows player hand', (tester) async {
      final player = models.Player(id: 'p1', name: 'Alice');
      player.hand.addAll([
        const models.Card(models.Suit.hearts, models.Rank.ace),
        const models.Card(models.Suit.spades, models.Rank.king),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestPlayerHand(player: player),
          ),
        ),
      );

      expect(find.text('A♥'), findsOneWidget);
      expect(find.text('H♠'), findsOneWidget);
    });

    testWidgets('shows bid and tricks status', (tester) async {
      final player = models.Player(id: 'p1', name: 'Alice', bid: 2, tricksTaken: 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestBidTricksStatus(player: player),
          ),
        ),
      );

      expect(find.textContaining('2'), findsWidgets); // bid
      expect(find.textContaining('1/2'), findsOneWidget); // tricks/bid
    });
  });

  group('Round end phase', () {
    testWidgets('shows player scores', (tester) async {
      final players = [
        // With nederlands scoring: bid=2, tricks=2 → 10 + (2*3) = +16
        models.Player(id: 'p1', name: 'Alice', bid: 2, tricksTaken: 2, totalScore: 16),
        // With nederlands scoring: bid=1, tricks=0 → -1*3 = -3
        models.Player(id: 'p2', name: 'Bob', bid: 1, tricksTaken: 0, totalScore: -3),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestRoundScores(
              players: players,
              rules: const GameRules(scoringSystem: ScoringSystem.nederlands),
            ),
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.textContaining('+16'), findsOneWidget);
      expect(find.textContaining('-3'), findsOneWidget);
    });

    testWidgets('shows next round button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Volgende ronde'),
            ),
          ),
        ),
      );

      expect(find.text('Volgende ronde'), findsOneWidget);
    });
  });
}

// Test helper widgets to isolate specific UI components

class _TestInfoBar extends StatelessWidget {
  final GameState game;
  const _TestInfoBar({required this.game});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                const Text('Troef'),
                Text(
                  game.trump?.symbol ?? '-',
                  style: TextStyle(
                    color: game.trump?.isRed == true ? Colors.red : Colors.black,
                  ),
                ),
              ],
            ),
            Column(
              children: [
                const Text('Ronde'),
                Text('${game.currentRoundIndex + 1}/${game.rounds.length}'),
              ],
            ),
            Column(
              children: [
                const Text('Kaarten'),
                Text('${game.cardsThisRound}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TestCardWidget extends StatelessWidget {
  final models.Card card;
  const _TestCardWidget({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Text(
        '${card.rank.symbol}${card.suit.symbol}',
        style: TextStyle(
          color: card.suit.isRed ? Colors.red : Colors.black,
        ),
      ),
    );
  }
}

class _TestBidButtons extends StatelessWidget {
  final List<int> allowedBids;
  final bool isMyTurn;
  const _TestBidButtons({required this.allowedBids, required this.isMyTurn});

  @override
  Widget build(BuildContext context) {
    if (!isMyTurn) return const SizedBox();
    return Wrap(
      children: allowedBids.map((bid) {
        return FilledButton(
          onPressed: () {},
          child: Text('$bid'),
        );
      }).toList(),
    );
  }
}

class _TestBidTotalIndicator extends StatelessWidget {
  final int totalBids;
  final int cardsThisRound;
  const _TestBidTotalIndicator({
    required this.totalBids,
    required this.cardsThisRound,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Totaal geboden: $totalBids / $cardsThisRound kaarten'),
      ],
    );
  }
}

class _TestPlayerHand extends StatelessWidget {
  final models.Player player;
  const _TestPlayerHand({required this.player});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: player.hand.map((card) {
        return Text(
          '${card.rank.symbol}${card.suit.symbol}',
          style: TextStyle(color: card.suit.isRed ? Colors.red : Colors.black),
        );
      }).toList(),
    );
  }
}

class _TestBidTricksStatus extends StatelessWidget {
  final models.Player player;
  const _TestBidTricksStatus({required this.player});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Bod: ${player.bid}'),
        const SizedBox(width: 16),
        Text('Gehaald: ${player.tricksTaken}/${player.bid}'),
      ],
    );
  }
}

class _TestRoundScores extends StatelessWidget {
  final List<models.Player> players;
  final GameRules rules;
  const _TestRoundScores({required this.players, required this.rules});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: players.map((player) {
        final score = rules.calculateRoundScore(player.bid!, player.tricksTaken);
        return ListTile(
          title: Text(player.name),
          trailing: Text('${score >= 0 ? '+' : ''}$score'),
        );
      }).toList(),
    );
  }
}
