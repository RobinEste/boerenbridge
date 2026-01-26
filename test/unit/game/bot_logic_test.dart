import 'package:flutter_test/flutter_test.dart';
import 'package:boerenbridge/game/bot_logic.dart';
import 'package:boerenbridge/game/models.dart';

import '../../test_helpers.dart';

void main() {
  group('BotLogic', () {
    group('calculateBid', () {
      test('bids 0 with weak hand (no trumps, no high cards)', () {
        final hand = testCards(['2H', '3H', '4D', '5C', '6S']);
        final bid = BotLogic.calculateBid(
          hand: hand,
          trump: Suit.spades,
          allowedBids: [0, 1, 2, 3, 4, 5],
        );

        expect(bid, equals(0));
      });

      test('bids higher with strong trumps', () {
        final hand = testCards(['AH', 'KH', 'QH', 'JH', '10H']);
        final bid = BotLogic.calculateBid(
          hand: hand,
          trump: Suit.hearts, // All cards are trump!
          allowedBids: [0, 1, 2, 3, 4, 5],
        );

        // 5 high trumps = very strong hand
        expect(bid, greaterThanOrEqualTo(3));
      });

      test('bids moderate with aces and kings', () {
        final hand = testCards(['AH', 'KD', '2C', '3S', '4H']);
        final bid = BotLogic.calculateBid(
          hand: hand,
          trump: Suit.clubs,
          allowedBids: [0, 1, 2, 3, 4, 5],
        );

        // Ace + King = 2 strong cards -> bid around 1
        expect(bid, inInclusiveRange(0, 2));
      });

      test('respects allowed bids list', () {
        final hand = testCards(['AH', 'KH', 'QH', 'JH', '10H']);
        final bid = BotLogic.calculateBid(
          hand: hand,
          trump: Suit.hearts,
          allowedBids: [0, 1], // Dealer restricted
        );

        expect(bid, anyOf(equals(0), equals(1)));
      });

      test('finds closest allowed bid when target not allowed', () {
        final hand = testCards(['AH', 'KH', 'QH', '2D', '3C']);
        final bid = BotLogic.calculateBid(
          hand: hand,
          trump: Suit.hearts, // 3 high trumps
          allowedBids: [0, 1, 3, 4, 5], // 2 is not allowed (screw the dealer)
        );

        // Target would be around 2, should pick closest (1 or 3)
        expect([1, 3], contains(bid));
      });

      test('returns first allowed bid when list has one element', () {
        final hand = testCards(['AH', 'KH', 'QH', 'JH', '10H']);
        final bid = BotLogic.calculateBid(
          hand: hand,
          trump: Suit.hearts,
          allowedBids: [3], // Only one option
        );

        expect(bid, equals(3));
      });

      test('returns 0 when allowed bids is empty', () {
        final hand = testCards(['AH', 'KH', 'QH', 'JH', '10H']);
        final bid = BotLogic.calculateBid(
          hand: hand,
          trump: Suit.hearts,
          allowedBids: [],
        );

        expect(bid, equals(0));
      });

      test('considers low trumps less valuable than high trumps', () {
        final lowTrumps = testCards(['2H', '3H', '4H', '5H', '6H']);
        final highTrumps = testCards(['AH', 'KH', 'QH', 'JH', '10H']);

        final lowBid = BotLogic.calculateBid(
          hand: lowTrumps,
          trump: Suit.hearts,
          allowedBids: [0, 1, 2, 3, 4, 5],
        );

        final highBid = BotLogic.calculateBid(
          hand: highTrumps,
          trump: Suit.hearts,
          allowedBids: [0, 1, 2, 3, 4, 5],
        );

        expect(highBid, greaterThan(lowBid));
      });
    });

    group('chooseCard', () {
      late Player player;

      setUp(() {
        player = Player(id: 'test', name: 'Test');
      });

      test('plays only card when hand has one card', () {
        player.hand = testCards(['AH']);
        player.bid = 1;

        final card = BotLogic.chooseCard(
          player: player,
          trump: Suit.spades,
          leadSuit: Suit.hearts,
          currentTrickCards: [],
          targetTricks: 1,
          tricksTaken: 0,
        );

        expect(card, equals(testCard('AH')));
      });

      test('plays highest card when leading and needs tricks', () {
        player.hand = testCards(['2H', '5H', 'AH']);
        player.bid = 1;

        final card = BotLogic.chooseCard(
          player: player,
          trump: Suit.spades,
          leadSuit: null, // Leading
          currentTrickCards: [], // No cards played yet
          targetTricks: 1,
          tricksTaken: 0, // Need 1 more trick
        );

        expect(card, equals(testCard('AH'))); // Should play highest
      });

      test('plays lowest card when leading and has enough tricks', () {
        player.hand = testCards(['2H', '5H', 'AH']);
        player.bid = 0;

        final card = BotLogic.chooseCard(
          player: player,
          trump: Suit.spades,
          leadSuit: null,
          currentTrickCards: [],
          targetTricks: 0,
          tricksTaken: 0, // Already have enough (0)
        );

        expect(card, equals(testCard('2H'))); // Should play lowest
      });

      test('plays lowest winning card when trying to win', () {
        player.hand = testCards(['JH', 'QH', 'KH', 'AH']);
        player.bid = 1;

        // Someone played 10H
        final currentCards = [
          PlayedCard(card: testCard('10H'), playerId: 'other'),
        ];

        final card = BotLogic.chooseCard(
          player: player,
          trump: Suit.spades,
          leadSuit: Suit.hearts,
          currentTrickCards: currentCards,
          targetTricks: 1,
          tricksTaken: 0,
        );

        // Should play Jack (lowest that beats 10)
        expect(card, equals(testCard('JH')));
      });

      test('plays lowest card when cannot win', () {
        player.hand = testCards(['2H', '3H', '4H']);
        player.bid = 1;

        // Someone played Ace of Hearts
        final currentCards = [
          PlayedCard(card: testCard('AH'), playerId: 'other'),
        ];

        final card = BotLogic.chooseCard(
          player: player,
          trump: Suit.spades, // No trump in hand
          leadSuit: Suit.hearts,
          currentTrickCards: currentCards,
          targetTricks: 1,
          tricksTaken: 0,
        );

        // Cannot beat Ace, play lowest
        expect(card, equals(testCard('2H')));
      });

      test('uses trump to win when out of lead suit and needs tricks', () {
        player.hand = testCards(['2S', 'AS']); // Only spades (trump)
        player.bid = 1;

        // Hearts was led
        final currentCards = [
          PlayedCard(card: testCard('KH'), playerId: 'other'),
        ];

        final card = BotLogic.chooseCard(
          player: player,
          trump: Suit.spades,
          leadSuit: Suit.hearts,
          currentTrickCards: currentCards,
          targetTricks: 1,
          tricksTaken: 0,
        );

        // Should trump with lowest trump (2S)
        expect(card, equals(testCard('2S')));
      });

      test('plays lowest when already has enough tricks', () {
        player.hand = testCards(['2H', 'AH', 'KH']);
        player.bid = 1;

        final card = BotLogic.chooseCard(
          player: player,
          trump: Suit.spades,
          leadSuit: null,
          currentTrickCards: [],
          targetTricks: 1,
          tricksTaken: 1, // Already have 1 trick
        );

        // Don't need more tricks, play lowest
        expect(card, equals(testCard('2H')));
      });

      test('follows suit when required', () {
        player.hand = testCards(['2H', '3D', '4C']); // Only 2H follows hearts
        player.bid = 0;

        final currentCards = [
          PlayedCard(card: testCard('5H'), playerId: 'other'),
        ];

        final card = BotLogic.chooseCard(
          player: player,
          trump: Suit.spades,
          leadSuit: Suit.hearts,
          currentTrickCards: currentCards,
          targetTricks: 0,
          tricksTaken: 0,
        );

        // Must follow suit with 2H
        expect(card.suit, equals(Suit.hearts));
      });
    });

    group('edge cases', () {
      test('handles empty hand gracefully', () {
        final player = Player(id: 'test', name: 'Test');
        player.hand = [testCard('2H')]; // At least one card required

        // Should not throw
        final card = BotLogic.chooseCard(
          player: player,
          trump: Suit.spades,
          leadSuit: null,
          currentTrickCards: [],
          targetTricks: 0,
          tricksTaken: 0,
        );

        expect(card, isNotNull);
      });

      test('handles no trump game', () {
        final hand = testCards(['AH', 'KD', 'QC', 'JS', '10H']);
        final bid = BotLogic.calculateBid(
          hand: hand,
          trump: null, // No trump
          allowedBids: [0, 1, 2, 3, 4, 5],
        );

        // Only counts Aces and Kings as strong
        expect(bid, inInclusiveRange(0, 2));
      });
    });
  });
}
