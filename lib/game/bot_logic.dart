import 'models.dart';

/// Bot logica voor Boerenbridge
/// Eenvoudige AI die redelijke beslissingen maakt voor bieden en kaart spelen
class BotLogic {
  BotLogic._();

  /// Bepaal een geschikt bod voor de bot gebaseerd op de hand
  static int calculateBid({
    required List<Card> hand,
    required Suit? trump,
    required List<int> allowedBids,
  }) {
    if (allowedBids.isEmpty) return 0;

    // Tel "sterke" kaarten: troef of hoge kaarten (B, V, H, A)
    int strongCards = 0;

    for (final card in hand) {
      // Troefkaarten zijn altijd sterk
      if (trump != null && card.suit == trump) {
        if (card.rank.value >= Rank.ten.value) {
          strongCards += 2; // Hoge troef is extra sterk
        } else {
          strongCards += 1;
        }
      }
      // Azen zijn sterk
      else if (card.rank == Rank.ace) {
        strongCards += 1;
      }
      // Heren zijn redelijk sterk
      else if (card.rank == Rank.king) {
        strongCards += 1;
      }
    }

    // Bid ongeveer 1/3 van de sterke kaarten, afgerond
    int targetBid = (strongCards / 3).round();

    // Zorg dat het bod binnen de toegestane range valt
    if (!allowedBids.contains(targetBid)) {
      // Vind het dichtstbijzijnde toegestane bod
      int closestBid = allowedBids.first;
      int minDiff = (targetBid - closestBid).abs();

      for (final bid in allowedBids) {
        final diff = (targetBid - bid).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestBid = bid;
        }
      }
      targetBid = closestBid;
    }

    return targetBid;
  }

  /// Kies een kaart om te spelen
  static Card chooseCard({
    required Player player,
    required Suit? trump,
    required Suit? leadSuit,
    required List<PlayedCard> currentTrickCards,
    required int targetTricks, // player.bid
    required int tricksTaken,  // player.tricksTaken
  }) {
    final playableCards = player.playableCards(leadSuit);
    if (playableCards.isEmpty) {
      // Zou niet moeten gebeuren, maar veiligheid
      return player.hand.first;
    }

    if (playableCards.length == 1) {
      return playableCards.first;
    }

    final needMoreTricks = tricksTaken < targetTricks;

    if (needMoreTricks) {
      // Probeer te winnen
      return _tryToWin(playableCards, currentTrickCards, trump, leadSuit);
    } else {
      // Probeer te verliezen - speel laagste kaart
      return _playLowest(playableCards);
    }
  }

  /// Probeer de slag te winnen met de laagst mogelijke winnende kaart
  static Card _tryToWin(
    List<Card> playableCards,
    List<PlayedCard> currentTrickCards,
    Suit? trump,
    Suit? leadSuit,
  ) {
    if (currentTrickCards.isEmpty) {
      // Eerste speler - speel een sterke kaart
      return _playHighest(playableCards);
    }

    // Vind de huidige winnende kaart
    final currentWinner = _findCurrentWinner(currentTrickCards, trump);

    // Vind kaarten die kunnen winnen
    final winningCards = playableCards.where((card) {
      return card.beats(currentWinner, trump, leadSuit ?? currentWinner.suit);
    }).toList();

    if (winningCards.isEmpty) {
      // Kan niet winnen - speel laagste
      return _playLowest(playableCards);
    }

    // Speel de laagste winnende kaart (zuinig spelen)
    return _playLowest(winningCards);
  }

  /// Vind de huidige winnende kaart in de trick
  static Card _findCurrentWinner(List<PlayedCard> cards, Suit? trump) {
    if (cards.isEmpty) throw ArgumentError('Cards list cannot be empty');

    Card winner = cards.first.card;
    final leadSuit = cards.first.card.suit;

    for (final played in cards.skip(1)) {
      if (played.card.beats(winner, trump, leadSuit)) {
        winner = played.card;
      }
    }

    return winner;
  }

  /// Speel de laagste kaart
  static Card _playLowest(List<Card> cards) {
    return cards.reduce((a, b) => a.rank.value < b.rank.value ? a : b);
  }

  /// Speel de hoogste kaart
  static Card _playHighest(List<Card> cards) {
    return cards.reduce((a, b) => a.rank.value > b.rank.value ? a : b);
  }
}
