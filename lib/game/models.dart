// Boerenbridge Game Models
// Pure Dart - geen Flutter dependencies, volledig testbaar

// =============================================================================
// ENUMS & VALUE OBJECTS
// =============================================================================

enum Suit { hearts, diamonds, clubs, spades }

enum Rank { two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace }

extension SuitExtension on Suit {
  String get symbol => switch (this) {
    Suit.hearts => '♥',
    Suit.diamonds => '♦',
    Suit.clubs => '♣',
    Suit.spades => '♠',
  };
  
  String get name => switch (this) {
    Suit.hearts => 'Harten',
    Suit.diamonds => 'Ruiten',
    Suit.clubs => 'Klaveren',
    Suit.spades => 'Schoppen',
  };
  
  bool get isRed => this == Suit.hearts || this == Suit.diamonds;
}

extension RankExtension on Rank {
  int get value => index + 2; // 2-14 (Ace high)
  
  String get symbol => switch (this) {
    Rank.two => '2',
    Rank.three => '3',
    Rank.four => '4',
    Rank.five => '5',
    Rank.six => '6',
    Rank.seven => '7',
    Rank.eight => '8',
    Rank.nine => '9',
    Rank.ten => '10',
    Rank.jack => 'B',  // Boer
    Rank.queen => 'V', // Vrouw
    Rank.king => 'H',  // Heer
    Rank.ace => 'A',
  };
}

// =============================================================================
// CARD
// =============================================================================

class Card {
  final Suit suit;
  final Rank rank;
  
  const Card(this.suit, this.rank);
  
  /// Vergelijk kaarten binnen een slag
  /// Returns true als deze kaart wint van [other]
  bool beats(Card other, Suit? trump, Suit leadSuit) {
    // Troef wint altijd van niet-troef
    if (suit == trump && other.suit != trump) return true;
    if (suit != trump && other.suit == trump) return false;
    
    // Beide troef of beide niet-troef: hoogste van de uitkomende kleur wint
    if (suit == leadSuit && other.suit != leadSuit) return true;
    if (suit != leadSuit && other.suit == leadSuit) return false;
    
    // Zelfde kleur: hoogste wint
    return rank.value > other.rank.value;
  }
  
  @override
  String toString() => '${rank.symbol}${suit.symbol}';
  
  @override
  bool operator ==(Object other) =>
      other is Card && suit == other.suit && rank == other.rank;
  
  @override
  int get hashCode => Object.hash(suit, rank);
  
  /// Voor serialisatie naar Supabase
  Map<String, dynamic> toJson() => {
    'suit': suit.index,
    'rank': rank.index,
  };
  
  factory Card.fromJson(Map<String, dynamic> json) => Card(
    Suit.values[json['suit'] as int],
    Rank.values[json['rank'] as int],
  );
}

// =============================================================================
// DECK
// =============================================================================

class Deck {
  final List<Card> _cards;
  
  Deck() : _cards = _createFullDeck();
  
  static List<Card> _createFullDeck() {
    return [
      for (final suit in Suit.values)
        for (final rank in Rank.values)
          Card(suit, rank),
    ];
  }
  
  void shuffle() {
    _cards.shuffle();
  }
  
  /// Deal [count] kaarten
  List<Card> deal(int count) {
    if (count > _cards.length) {
      throw StateError('Niet genoeg kaarten in deck');
    }
    return [for (var i = 0; i < count; i++) _cards.removeLast()];
  }
  
  int get remaining => _cards.length;
  
  /// Reset deck voor nieuwe ronde
  void reset() {
    _cards.clear();
    _cards.addAll(_createFullDeck());
  }
}

// =============================================================================
// PLAYER
// =============================================================================

class Player {
  final String id;        // game_players.id (database row ID)
  final String? odataId;   // user_id (Supabase auth user ID) for matching current user
  final String name;
  List<Card> hand;
  int? bid;           // Geboden aantal slagen
  int tricksTaken;    // Behaalde slagen deze ronde
  int totalScore;     // Totaalscore over alle rondes

  Player({
    required this.id,
    this.odataId,
    required this.name,
    List<Card>? hand,
    this.bid,
    this.tricksTaken = 0,
    this.totalScore = 0,
  }) : hand = hand ?? [];

  /// Check of dit de huidige gebruiker is
  bool isCurrentUser(String? currentUserId) => odataId == currentUserId;
  
  /// Kan deze speler deze kaart spelen gegeven de uitkomende kleur?
  bool canPlay(Card card, Suit? leadSuit) {
    // Eerste speler mag alles spelen
    if (leadSuit == null) return true;
    
    // Als je de kleur hebt, moet je bekennen
    final hasLeadSuit = hand.any((c) => c.suit == leadSuit);
    if (hasLeadSuit) {
      return card.suit == leadSuit;
    }
    
    // Anders mag je alles spelen
    return true;
  }
  
  /// Speelbare kaarten gegeven de huidige slag
  List<Card> playableCards(Suit? leadSuit) {
    if (leadSuit == null) return List.from(hand);
    
    final suitCards = hand.where((c) => c.suit == leadSuit).toList();
    return suitCards.isNotEmpty ? suitCards : List.from(hand);
  }
  
  void playCard(Card card) {
    hand.remove(card);
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': odataId,
    'name': name,
    'hand': hand.map((c) => c.toJson()).toList(),
    'bid': bid,
    'tricks_taken': tricksTaken,
    'total_score': totalScore,
  };

  factory Player.fromJson(Map<String, dynamic> json) => Player(
    id: json['id'] as String,
    odataId: json['user_id'] as String?,
    name: json['name'] as String,
    hand: (json['hand'] as List?)
        ?.map((c) => Card.fromJson(c as Map<String, dynamic>))
        .toList() ?? [],
    bid: json['bid'] as int?,
    tricksTaken: json['tricks_taken'] as int? ?? 0,
    totalScore: json['total_score'] as int? ?? 0,
  );
}

// =============================================================================
// TRICK (SLAG)
// =============================================================================

class Trick {
  final List<PlayedCard> cards;
  final Suit? trump;
  
  Trick({required this.trump}) : cards = [];
  
  Suit? get leadSuit => cards.isNotEmpty ? cards.first.card.suit : null;
  
  void addCard(String playerId, Card card) {
    cards.add(PlayedCard(playerId: playerId, card: card));
  }
  
  /// Bepaal de winnaar van de slag
  String? get winnerId {
    if (cards.isEmpty) return null;
    
    var winner = cards.first;
    for (final played in cards.skip(1)) {
      if (played.card.beats(winner.card, trump, leadSuit!)) {
        winner = played;
      }
    }
    return winner.playerId;
  }
  
  bool get isComplete => cards.length >= 4; // Aanpassen voor speelersaantal
  
  Map<String, dynamic> toJson() => {
    'cards': cards.map((pc) => pc.toJson()).toList(),
    'trump': trump?.index,
  };

  factory Trick.fromJson(Map<String, dynamic> json) {
    final trick = Trick(
      trump: json['trump'] != null ? Suit.values[json['trump'] as int] : null,
    );
    final cardsList = json['cards'] as List?;
    if (cardsList != null) {
      for (final pc in cardsList) {
        final playedCard = PlayedCard.fromJson(pc as Map<String, dynamic>);
        trick.cards.add(playedCard);
      }
    }
    return trick;
  }
}

class PlayedCard {
  final String playerId;
  final Card card;

  PlayedCard({required this.playerId, required this.card});

  Map<String, dynamic> toJson() => {
    'player_id': playerId,
    'card': card.toJson(),
  };

  factory PlayedCard.fromJson(Map<String, dynamic> json) => PlayedCard(
    playerId: json['player_id'] as String,
    card: Card.fromJson(json['card'] as Map<String, dynamic>),
  );
}
