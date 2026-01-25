import 'package:flutter_test/flutter_test.dart';
import 'package:boerenbridge/game/models.dart';

void main() {
  group('Card', () {
    test('creates card with suit and rank', () {
      const card = Card(Suit.hearts, Rank.ace);
      expect(card.suit, equals(Suit.hearts));
      expect(card.rank, equals(Rank.ace));
    });

    test('toString returns correct format', () {
      const card = Card(Suit.hearts, Rank.ace);
      expect(card.toString(), equals('A♥'));
    });

    test('equality works correctly', () {
      const card1 = Card(Suit.hearts, Rank.ace);
      const card2 = Card(Suit.hearts, Rank.ace);
      const card3 = Card(Suit.spades, Rank.ace);

      expect(card1, equals(card2));
      expect(card1, isNot(equals(card3)));
    });

    group('beats', () {
      test('trump beats non-trump', () {
        const trumpCard = Card(Suit.hearts, Rank.two);
        const nonTrumpCard = Card(Suit.spades, Rank.ace);

        expect(
          trumpCard.beats(nonTrumpCard, Suit.hearts, Suit.spades),
          isTrue,
        );
      });

      test('non-trump loses to trump', () {
        const trumpCard = Card(Suit.hearts, Rank.two);
        const nonTrumpCard = Card(Suit.spades, Rank.ace);

        expect(
          nonTrumpCard.beats(trumpCard, Suit.hearts, Suit.spades),
          isFalse,
        );
      });

      test('lead suit beats non-lead suit when no trump', () {
        const leadCard = Card(Suit.spades, Rank.two);
        const otherCard = Card(Suit.diamonds, Rank.ace);

        expect(
          leadCard.beats(otherCard, null, Suit.spades),
          isTrue,
        );
      });

      test('higher rank wins same suit', () {
        const highCard = Card(Suit.hearts, Rank.king);
        const lowCard = Card(Suit.hearts, Rank.queen);

        expect(
          highCard.beats(lowCard, null, Suit.hearts),
          isTrue,
        );
      });
    });

    group('serialization', () {
      test('toJson returns correct map', () {
        const card = Card(Suit.hearts, Rank.ace);
        final json = card.toJson();

        expect(json['suit'], equals(Suit.hearts.index));
        expect(json['rank'], equals(Rank.ace.index));
      });

      test('fromJson creates correct card', () {
        final json = {'suit': Suit.hearts.index, 'rank': Rank.ace.index};
        final card = Card.fromJson(json);

        expect(card.suit, equals(Suit.hearts));
        expect(card.rank, equals(Rank.ace));
      });

      test('roundtrip preserves card', () {
        const original = Card(Suit.diamonds, Rank.jack);
        final json = original.toJson();
        final restored = Card.fromJson(json);

        expect(restored, equals(original));
      });
    });
  });

  group('Deck', () {
    test('creates 52 cards', () {
      final deck = Deck();
      expect(deck.remaining, equals(52));
    });

    test('deal removes cards from deck', () {
      final deck = Deck();
      final cards = deck.deal(5);

      expect(cards.length, equals(5));
      expect(deck.remaining, equals(47));
    });

    test('deal throws when not enough cards', () {
      final deck = Deck();
      deck.deal(50);

      expect(() => deck.deal(5), throwsStateError);
    });

    test('reset restores full deck', () {
      final deck = Deck();
      deck.deal(30);
      deck.reset();

      expect(deck.remaining, equals(52));
    });

    test('shuffle changes card order', () {
      final deck1 = Deck();
      final deck2 = Deck();

      deck2.shuffle();

      // Deal all cards and compare - very unlikely to be same after shuffle
      final cards1 = deck1.deal(52);
      final cards2 = deck2.deal(52);

      // At least some cards should be in different positions
      var differences = 0;
      for (var i = 0; i < 52; i++) {
        if (cards1[i] != cards2[i]) differences++;
      }
      expect(differences, greaterThan(0));
    });
  });

  group('Player', () {
    test('creates player with required fields', () {
      final player = Player(id: 'p1', name: 'Alice');

      expect(player.id, equals('p1'));
      expect(player.name, equals('Alice'));
      expect(player.hand, isEmpty);
      expect(player.bid, isNull);
      expect(player.tricksTaken, equals(0));
      expect(player.totalScore, equals(0));
    });

    test('isCurrentUser matches odataId', () {
      final player = Player(id: 'db-id', odataId: 'auth-id', name: 'Alice');

      expect(player.isCurrentUser('auth-id'), isTrue);
      expect(player.isCurrentUser('other-id'), isFalse);
      expect(player.isCurrentUser(null), isFalse);
    });

    group('canPlay', () {
      test('can play any card when no lead suit', () {
        final player = Player(id: 'p1', name: 'Alice');
        player.hand.addAll([
          const Card(Suit.hearts, Rank.ace),
          const Card(Suit.spades, Rank.king),
        ]);

        expect(player.canPlay(player.hand[0], null), isTrue);
        expect(player.canPlay(player.hand[1], null), isTrue);
      });

      test('must follow suit when has lead suit', () {
        final player = Player(id: 'p1', name: 'Alice');
        player.hand.addAll([
          const Card(Suit.hearts, Rank.ace),
          const Card(Suit.spades, Rank.king),
        ]);

        expect(player.canPlay(player.hand[0], Suit.hearts), isTrue);
        expect(player.canPlay(player.hand[1], Suit.hearts), isFalse);
      });

      test('can play any card when does not have lead suit', () {
        final player = Player(id: 'p1', name: 'Alice');
        player.hand.addAll([
          const Card(Suit.hearts, Rank.ace),
          const Card(Suit.spades, Rank.king),
        ]);

        expect(player.canPlay(player.hand[0], Suit.diamonds), isTrue);
        expect(player.canPlay(player.hand[1], Suit.diamonds), isTrue);
      });
    });

    test('playCard removes card from hand', () {
      final player = Player(id: 'p1', name: 'Alice');
      const card = Card(Suit.hearts, Rank.ace);
      player.hand.add(card);

      player.playCard(card);

      expect(player.hand, isEmpty);
    });

    group('serialization', () {
      test('toJson includes all fields', () {
        final player = Player(
          id: 'p1',
          odataId: 'auth-1',
          name: 'Alice',
          hand: [const Card(Suit.hearts, Rank.ace)],
          bid: 2,
          tricksTaken: 1,
          totalScore: 12,
        );

        final json = player.toJson();

        expect(json['id'], equals('p1'));
        expect(json['user_id'], equals('auth-1'));
        expect(json['name'], equals('Alice'));
        expect(json['hand'], hasLength(1));
        expect(json['bid'], equals(2));
        expect(json['tricks_taken'], equals(1));
        expect(json['total_score'], equals(12));
      });

      test('fromJson restores all fields', () {
        final json = {
          'id': 'p1',
          'user_id': 'auth-1',
          'name': 'Alice',
          'hand': [
            {'suit': Suit.hearts.index, 'rank': Rank.ace.index}
          ],
          'bid': 2,
          'tricks_taken': 1,
          'total_score': 12,
        };

        final player = Player.fromJson(json);

        expect(player.id, equals('p1'));
        expect(player.odataId, equals('auth-1'));
        expect(player.name, equals('Alice'));
        expect(player.hand, hasLength(1));
        expect(player.bid, equals(2));
        expect(player.tricksTaken, equals(1));
        expect(player.totalScore, equals(12));
      });

      test('roundtrip preserves player', () {
        final original = Player(
          id: 'p1',
          odataId: 'auth-1',
          name: 'Alice',
          hand: [const Card(Suit.hearts, Rank.ace)],
          bid: 2,
          tricksTaken: 1,
          totalScore: 12,
        );

        final json = original.toJson();
        final restored = Player.fromJson(json);

        expect(restored.id, equals(original.id));
        expect(restored.odataId, equals(original.odataId));
        expect(restored.name, equals(original.name));
        expect(restored.hand.length, equals(original.hand.length));
        expect(restored.bid, equals(original.bid));
        expect(restored.tricksTaken, equals(original.tricksTaken));
        expect(restored.totalScore, equals(original.totalScore));
      });
    });
  });

  group('Trick', () {
    test('creates empty trick', () {
      final trick = Trick(trump: Suit.hearts);

      expect(trick.cards, isEmpty);
      expect(trick.trump, equals(Suit.hearts));
      expect(trick.leadSuit, isNull);
    });

    test('leadSuit returns first card suit', () {
      final trick = Trick(trump: Suit.hearts);
      trick.addCard('p1', const Card(Suit.spades, Rank.ace));

      expect(trick.leadSuit, equals(Suit.spades));
    });

    test('winnerId returns correct winner', () {
      final trick = Trick(trump: Suit.hearts);
      trick.addCard('p1', const Card(Suit.spades, Rank.king));
      trick.addCard('p2', const Card(Suit.spades, Rank.ace));
      trick.addCard('p3', const Card(Suit.spades, Rank.queen));

      expect(trick.winnerId, equals('p2'));
    });

    test('trump wins over higher non-trump', () {
      final trick = Trick(trump: Suit.hearts);
      trick.addCard('p1', const Card(Suit.spades, Rank.ace));
      trick.addCard('p2', const Card(Suit.hearts, Rank.two));

      expect(trick.winnerId, equals('p2'));
    });

    group('serialization', () {
      test('toJson includes all fields', () {
        final trick = Trick(trump: Suit.hearts);
        trick.addCard('p1', const Card(Suit.spades, Rank.ace));

        final json = trick.toJson();

        expect(json['trump'], equals(Suit.hearts.index));
        expect(json['cards'], hasLength(1));
      });

      test('fromJson restores trick', () {
        final json = {
          'trump': Suit.hearts.index,
          'cards': [
            {
              'player_id': 'p1',
              'card': {'suit': Suit.spades.index, 'rank': Rank.ace.index}
            }
          ],
        };

        final trick = Trick.fromJson(json);

        expect(trick.trump, equals(Suit.hearts));
        expect(trick.cards, hasLength(1));
        expect(trick.cards[0].playerId, equals('p1'));
      });

      test('roundtrip preserves trick', () {
        final original = Trick(trump: Suit.diamonds);
        original.addCard('p1', const Card(Suit.spades, Rank.ace));
        original.addCard('p2', const Card(Suit.spades, Rank.king));

        final json = original.toJson();
        final restored = Trick.fromJson(json);

        expect(restored.trump, equals(original.trump));
        expect(restored.cards.length, equals(original.cards.length));
        expect(restored.winnerId, equals(original.winnerId));
      });
    });
  });

  group('PlayedCard', () {
    test('creates with player and card', () {
      final playedCard = PlayedCard(
        playerId: 'p1',
        card: const Card(Suit.hearts, Rank.ace),
      );

      expect(playedCard.playerId, equals('p1'));
      expect(playedCard.card.suit, equals(Suit.hearts));
    });

    test('serialization roundtrip', () {
      final original = PlayedCard(
        playerId: 'p1',
        card: const Card(Suit.hearts, Rank.ace),
      );

      final json = original.toJson();
      final restored = PlayedCard.fromJson(json);

      expect(restored.playerId, equals(original.playerId));
      expect(restored.card, equals(original.card));
    });
  });
}
