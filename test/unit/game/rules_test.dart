import 'package:flutter_test/flutter_test.dart';
import 'package:boerenbridge/game/rules.dart';

void main() {
  group('ScoringSystem', () {
    group('basis', () {
      const rules = GameRules(scoringSystem: ScoringSystem.basis);

      test('correct bid gives 10 + 2*tricks', () {
        expect(rules.calculateRoundScore(0, 0), equals(10));
        expect(rules.calculateRoundScore(1, 1), equals(12));
        expect(rules.calculateRoundScore(3, 3), equals(16));
        expect(rules.calculateRoundScore(5, 5), equals(20));
      });

      test('wrong bid gives 0', () {
        expect(rules.calculateRoundScore(2, 0), equals(0));
        expect(rules.calculateRoundScore(0, 1), equals(0));
        expect(rules.calculateRoundScore(3, 5), equals(0));
      });
    });

    group('vlaams', () {
      const rules = GameRules(scoringSystem: ScoringSystem.vlaams);

      test('correct bid gives 10 + 3*tricks', () {
        expect(rules.calculateRoundScore(0, 0), equals(10));
        expect(rules.calculateRoundScore(1, 1), equals(13));
        expect(rules.calculateRoundScore(3, 3), equals(19));
      });

      test('wrong bid gives 0', () {
        expect(rules.calculateRoundScore(2, 0), equals(0));
      });
    });

    group('nederlands', () {
      const rules = GameRules(scoringSystem: ScoringSystem.nederlands);

      test('correct bid gives 10 + 3*tricks', () {
        expect(rules.calculateRoundScore(0, 0), equals(10));
        expect(rules.calculateRoundScore(1, 1), equals(13));
        expect(rules.calculateRoundScore(3, 3), equals(19));
        expect(rules.calculateRoundScore(5, 5), equals(25));
      });

      test('wrong bid gives -3 per difference', () {
        expect(rules.calculateRoundScore(3, 1), equals(-6)); // 2 off * -3
        expect(rules.calculateRoundScore(0, 2), equals(-6)); // 2 off * -3
        expect(rules.calculateRoundScore(5, 2), equals(-9)); // 3 off * -3
        expect(rules.calculateRoundScore(1, 0), equals(-3)); // 1 off * -3
      });
    });

    group('zeroBidBonus', () {
      test('adds bonus when bidding and making 0', () {
        const rules = GameRules(
          scoringSystem: ScoringSystem.basis,
          zeroBidBonus: 5,
        );

        expect(rules.calculateRoundScore(0, 0), equals(15)); // 10 + 5 bonus
        expect(rules.calculateRoundScore(1, 1), equals(12)); // no bonus
      });
    });
  });

  group('RoundSequence', () {
    test('pyramid generates 1 to max to 1', () {
      final rounds = RoundSequence.pyramid.generateRounds(4);
      // 52/4 = 13 max cards
      expect(rounds.first, equals(1));
      expect(rounds[12], equals(13)); // middle
      expect(rounds.last, equals(1));
      expect(rounds.length, equals(25)); // 1-13 + 12-1
    });

    test('ascending generates 1 to max', () {
      final rounds = RoundSequence.ascending.generateRounds(4);
      expect(rounds.first, equals(1));
      expect(rounds.last, equals(13));
      expect(rounds.length, equals(13));
    });

    test('descending generates max to 1', () {
      final rounds = RoundSequence.descending.generateRounds(4);
      expect(rounds.first, equals(13));
      expect(rounds.last, equals(1));
      expect(rounds.length, equals(13));
    });
  });

  group('GameRules', () {
    group('getRounds', () {
      test('respects maxRounds limit', () {
        const rules = GameRules(maxRounds: 5);
        final rounds = rules.getRounds(4);

        expect(rounds.length, equals(5));
        expect(rounds, equals([1, 2, 3, 4, 5]));
      });

      test('returns full rounds when maxRounds is null', () {
        const rules = GameRules();
        final rounds = rules.getRounds(4);

        expect(rounds.length, equals(25)); // full pyramid
      });

      test('uses custom rounds when specified', () {
        const rules = GameRules(
          roundSequence: RoundSequence.custom,
          customRounds: [5, 4, 3, 2, 1],
        );
        final rounds = rules.getRounds(4);

        expect(rounds, equals([5, 4, 3, 2, 1]));
      });
    });

    group('allowedBidsForDealer', () {
      test('screw the dealer prevents exact match', () {
        const rules = GameRules(screwTheDealer: true, allowZeroBid: true);

        // 5 cards, 3 already bid = dealer cannot bid 2
        final allowed = rules.allowedBidsForDealer(5, 3);

        expect(allowed, contains(0));
        expect(allowed, contains(1));
        expect(allowed, isNot(contains(2))); // forbidden
        expect(allowed, contains(3));
        expect(allowed, contains(4));
        expect(allowed, contains(5));
      });

      test('allows all bids when screw the dealer is off', () {
        const rules = GameRules(screwTheDealer: false, allowZeroBid: true);

        final allowed = rules.allowedBidsForDealer(5, 3);

        expect(allowed, contains(2)); // now allowed
      });

      test('respects allowZeroBid setting', () {
        const rulesWithZero = GameRules(allowZeroBid: true);
        const rulesWithoutZero = GameRules(allowZeroBid: false);

        expect(rulesWithZero.allowedBidsForDealer(5, 0), contains(0));
        expect(rulesWithoutZero.allowedBidsForDealer(5, 0), isNot(contains(0)));
      });
    });

    group('serialization', () {
      test('toJson includes all fields', () {
        const rules = GameRules(
          scoringSystem: ScoringSystem.nederlands,
          roundSequence: RoundSequence.ascending,
          maxRounds: 10,
          screwTheDealer: false,
          allowZeroBid: false,
          zeroBidBonus: 5,
        );

        final json = rules.toJson();

        expect(json['scoring_system'], equals(ScoringSystem.nederlands.index));
        expect(json['round_sequence'], equals(RoundSequence.ascending.index));
        expect(json['max_rounds'], equals(10));
        expect(json['screw_the_dealer'], isFalse);
        expect(json['allow_zero_bid'], isFalse);
        expect(json['zero_bid_bonus'], equals(5));
      });

      test('fromJson restores all fields', () {
        final json = {
          'scoring_system': ScoringSystem.nederlands.index,
          'round_sequence': RoundSequence.ascending.index,
          'max_rounds': 10,
          'screw_the_dealer': false,
          'allow_zero_bid': false,
          'zero_bid_bonus': 5,
        };

        final rules = GameRules.fromJson(json);

        expect(rules.scoringSystem, equals(ScoringSystem.nederlands));
        expect(rules.roundSequence, equals(RoundSequence.ascending));
        expect(rules.maxRounds, equals(10));
        expect(rules.screwTheDealer, isFalse);
        expect(rules.allowZeroBid, isFalse);
        expect(rules.zeroBidBonus, equals(5));
      });

      test('roundtrip preserves rules', () {
        const original = GameRules(
          scoringSystem: ScoringSystem.vlaams,
          maxRounds: 15,
          zeroBidBonus: 3,
        );

        final json = original.toJson();
        final restored = GameRules.fromJson(json);

        expect(restored.scoringSystem, equals(original.scoringSystem));
        expect(restored.maxRounds, equals(original.maxRounds));
        expect(restored.zeroBidBonus, equals(original.zeroBidBonus));
      });
    });

    group('copyWith', () {
      test('creates copy with changed fields', () {
        const original = GameRules(
          scoringSystem: ScoringSystem.basis,
          maxRounds: 10,
        );

        final modified = original.copyWith(
          scoringSystem: ScoringSystem.nederlands,
          maxRounds: 5,
        );

        expect(modified.scoringSystem, equals(ScoringSystem.nederlands));
        expect(modified.maxRounds, equals(5));
        // Unchanged fields preserved
        expect(modified.screwTheDealer, equals(original.screwTheDealer));
      });
    });
  });

  group('preset rules', () {
    test('dutch has correct defaults', () {
      expect(GameRules.dutch.scoringSystem, equals(ScoringSystem.nederlands));
      expect(GameRules.dutch.screwTheDealer, isTrue);
      expect(GameRules.dutch.allowZeroBid, isTrue);
    });

    test('flemish has correct defaults', () {
      expect(GameRules.flemish.scoringSystem, equals(ScoringSystem.vlaams));
      expect(GameRules.flemish.screwTheDealer, isTrue);
      expect(GameRules.flemish.allowZeroBid, isTrue);
    });

    test('basic has correct defaults', () {
      expect(GameRules.basic.scoringSystem, equals(ScoringSystem.basis));
      expect(GameRules.basic.screwTheDealer, isTrue);
      expect(GameRules.basic.allowZeroBid, isTrue);
    });
  });
}
