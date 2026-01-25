# Boerenbridge App - Development Guide voor Claude Code

## Project Overzicht

Een Nederlandse multiplayer Boerenbridge (Oh Hell) kaartspel app voor iOS, Android en Web.

### Doelstellingen
1. **MVP**: Spelen met vrienden via een 4-letter code
2. **Commercieel**: Premium features (custom regels, geen ads) via "Jackbox model" (host betaalt)
3. **Markt**: Benelux - er is geen goede Nederlandse Boerenbridge app

### Tech Stack
| Component | Keuze | Reden |
|-----------|-------|-------|
| Frontend | Flutter | Cross-platform, smooth animaties |
| Backend | Supabase | Gratis tier, ingebouwde Realtime, geen server beheer |
| State | Riverpod | Type-safe, testbaar |
| Database | PostgreSQL (via Supabase) | ACID, Row Level Security |
| Real-time | Supabase Realtime | WebSocket abstraction |

---

## Architectuur

### Project Structuur
```
boerenbridge/
├── lib/
│   ├── game/                    # DONE - Pure Dart game logic
│   │   ├── models.dart          # Card, Player, Trick, Deck
│   │   ├── rules.dart           # Configureerbare spelregels
│   │   └── game_state.dart      # State machine
│   │
│   ├── services/                # DONE - Backend integratie
│   │   └── supabase_service.dart
│   │
│   ├── providers/               # TODO - Riverpod state
│   │   ├── game_provider.dart
│   │   ├── auth_provider.dart
│   │   └── settings_provider.dart
│   │
│   ├── screens/                 # TODO - UI schermen
│   │   ├── home_screen.dart     # PARTIAL - basis aanwezig
│   │   ├── lobby_screen.dart    # TODO
│   │   ├── game_screen.dart     # TODO
│   │   ├── settings_screen.dart # TODO
│   │   └── results_screen.dart  # TODO
│   │
│   ├── widgets/                 # TODO - Game widgets
│   │   ├── card_widget.dart
│   │   ├── hand_widget.dart
│   │   ├── trick_widget.dart
│   │   ├── bid_selector.dart
│   │   └── scoreboard.dart
│   │
│   └── main.dart                # DONE - App entry point
│
├── supabase/
│   └── schema.sql               # DONE - Database schema
│
├── test/
│   └── game/
│       └── game_test.dart       # DONE - Unit tests
│
└── pubspec.yaml                 # DONE
```

### Data Flow
```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Flutter   │────▶│   Riverpod   │────▶│  Supabase   │
│   Widgets   │◀────│   Providers  │◀────│  Realtime   │
└─────────────┘     └──────────────┘     └─────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  Game Logic  │
                    │  (Pure Dart) │
                    └──────────────┘
```

---

## Game Logic (Reeds Geïmplementeerd)

### Spelregels Configuratie
```dart
// Beschikbare presets
GameRules.dutch    // Standaard: +10 bonus, +2 per slag
GameRules.flemish  // Vlaams: +10 bonus, +3 per slag
GameRules.quick    // Alleen oplopend (sneller)

// Custom regels
GameRules(
  scoringSystem: ScoringSystem.standard,     // standard, flemish, bonusOnly, withPenalty
  roundSequence: RoundSequence.pyramid,      // pyramid, ascending, descending, custom
  trumpDetermination: TrumpDetermination.topCard,
  screwTheDealer: true,                      // Deler mag niet "kloppen"
  allowZeroBid: true,
  zeroBidBonus: 0,                           // Extra punten voor 0 correct
)
```

### Game State Machine
```
GamePhase.lobby      → Wachten op spelers
GamePhase.bidding    → Kaarten gedeeld, spelers bieden
GamePhase.playing    → Slagen worden gespeeld
GamePhase.roundEnd   → Scores berekend
GamePhase.gameEnd    → Spel afgelopen
```

### Belangrijke Methodes
```dart
// GameState
game.startGame()                    // Start vanuit lobby
game.placeBid(playerId, bid)        // Plaats bod
game.playCard(playerId, card)       // Speel kaart
game.nextRound()                    // Volgende ronde
game.toPlayerView(playerId)         // Verbergt kaarten van anderen

// Player
player.canPlay(card, leadSuit)      // Mag deze kaart gespeeld worden?
player.playableCards(leadSuit)      // Welke kaarten mogen?

// Card
card.beats(other, trump, leadSuit)  // Wint deze kaart?
```

---

## Database Schema (Reeds Geïmplementeerd)

### Tabellen
| Tabel | Doel |
|-------|------|
| `games` | Spelinstanties met join_code en rules |
| `game_players` | Koppeling spelers aan games |
| `game_state` | Live spelstaat (realtime sync) |
| `game_actions` | Audit log voor replay/debugging |

### Realtime Subscriptions
- `game_state` → Automatisch naar alle spelers gepusht
- `game_players` → Updates bij join/leave

### Row Level Security
- Spelers kunnen alleen games zien waar ze in zitten
- Alleen host kan game settings wijzigen

---

## TODO: Wat Nog Gebouwd Moet Worden

### 1. Riverpod Providers (Prioriteit: Hoog)

```dart
// lib/providers/game_provider.dart

@riverpod
class GameNotifier extends _$GameNotifier {
  @override
  AsyncValue<GameState?> build() => const AsyncValue.data(null);
  
  Future<void> createGame(String hostName, GameRules rules) async { ... }
  Future<void> joinGame(String code, String playerName) async { ... }
  Future<void> startGame() async { ... }
  Future<void> placeBid(int bid) async { ... }
  Future<void> playCard(Card card) async { ... }
}

// lib/providers/auth_provider.dart
@riverpod
class Auth extends _$Auth {
  // Anonieme auth + persistente guest ID
}
```

### 2. Lobby Screen (Prioriteit: Hoog)

**Features:**
- Toon join code groot in beeld (kopieerbaar)
- Lijst van spelers die gejoined zijn (realtime)
- "Start Spel" knop (alleen voor host)
- Regels configuratie (premium feature later)

**UI Sketch:**
```
┌────────────────────────────┐
│  ← Terug                   │
│                            │
│     Deel deze code:        │
│    ┌────────────────┐      │
│    │     ABCD       │ 📋   │
│    └────────────────┘      │
│                            │
│  Spelers (3/6):            │
│  ✓ Robin (host)            │
│  ✓ Jan                     │
│  ✓ Piet                    │
│  ○ Wachten...              │
│                            │
│  ┌────────────────────┐    │
│  │   Start Spel ▶     │    │
│  └────────────────────┘    │
└────────────────────────────┘
```

### 3. Game Screen (Prioriteit: Hoog)

**Componenten:**

#### A. Hand Widget
- Kaarten in een "waaier" onderaan scherm
- Tap to select, tap to play (twee stappen)
- Niet-speelbare kaarten grayed out
- Landschap modus ondersteuning

#### B. Trick Widget (midden van scherm)
- Gespeelde kaarten van alle spelers
- Animatie: kaart vliegt naar midden
- Winnaar highlight na slag

#### C. Bid Selector
- Alleen zichtbaar in bidding fase
- Knoppen 0, 1, 2, ... tot max
- Disabled knop voor "screw the dealer"
- Toon wat anderen geboden hebben

#### D. Scoreboard
- Altijd toegankelijk via knop
- Toon per ronde: bod vs gehaald
- Running totaal

#### E. Info Bar (bovenaan)
- Huidige troef (groot icoon)
- Ronde X van Y
- Wie is aan de beurt

**UI Sketch (landscape):**
```
┌─────────────────────────────────────────────────┐
│ ♥ Troef   │  Ronde 5/17  │  Score: 42  │  ⚙️   │
├─────────────────────────────────────────────────┤
│                                                 │
│     Jan          [♠K]        Piet              │
│     Bod: 2        │         Bod: 1             │
│                   │                            │
│         [♥7]──────┼──────[♦A]                  │
│                   │                            │
│                   │                            │
│                                                 │
├─────────────────────────────────────────────────┤
│                                                 │
│   [♠2][♠5][♠J][♥3][♥9][♦4][♦8][♣K]            │
│                  ↑                              │
│              Jouw beurt                         │
└─────────────────────────────────────────────────┘
```

### 4. Card Widget (Prioriteit: Hoog)

```dart
// Gewenste API
CardWidget(
  card: Card(Suit.hearts, Rank.ace),
  size: CardSize.medium,        // small, medium, large
  isPlayable: true,             // false = grayed out
  isSelected: false,            // highlight wanneer geselecteerd
  isFaceDown: false,            // voor andere spelers
  onTap: () {},
)
```

**Design richtlijnen:**
- Standaard kaart design (wit met rood/zwart)
- Kleurenblind optie: 4-kleuren deck
- Animaties met flutter_animate package
- Haptische feedback bij selectie

### 5. Reconnect Logic (Prioriteit: Medium)

**Scenario's:**
1. WiFi → 4G switch
2. App naar achtergrond
3. Telefoon in slaapstand

**Implementatie:**
```dart
class ConnectionManager {
  // Detecteer disconnect
  // Probeer automatisch reconnect (max 60 sec)
  // Toon UI feedback ("Verbinding verbroken...")
  // Bij reconnect: vraag state dump van server
  // Bot neemt over na timeout
}
```

### 6. Bot Logic (Prioriteit: Medium)

Simpele bot voor als speler disconnect:
```dart
class SimpleBot {
  int decideBid(List<Card> hand, int cardsInRound, Suit? trump) {
    // Tel "zekere" slagen (Azen, troef hoog)
    // Return conservatieve schatting
  }
  
  Card decidePlay(List<Card> hand, Trick currentTrick, Suit? trump) {
    // Als eerste: speel laagste kaart
    // Als moet bekennen: speel laagste van kleur
    // Anders: gooi laagste weg
  }
}
```

### 7. Settings Screen (Prioriteit: Laag)

- Spelernaam wijzigen
- Kleurenblind modus
- Geluidseffecten aan/uit
- Taal (NL/VL)

### 8. Premium Features (Prioriteit: Later)

- Custom regels configuratie
- Statistieken historie
- Geen advertenties
- "Speciale kaarten" variant (Wizard-style)

---

## Setup Instructies

### 1. Flutter Project Aanmaken
```bash
flutter create --org nl.bertus boerenbridge
cd boerenbridge
```

### 2. Dependencies Installeren
```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.3.0
  flutter_riverpod: ^2.4.0
  riverpod_annotation: ^2.3.0
  go_router: ^13.0.0
  flutter_animate: ^4.3.0
  google_fonts: ^6.1.0
  uuid: ^4.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  riverpod_generator: ^2.3.0
  build_runner: ^2.4.0
```

### 3. Supabase Setup
1. Maak project op supabase.com
2. Ga naar SQL Editor
3. Voer `supabase/schema.sql` uit
4. Kopieer URL + anon key naar config

### 4. Bestanden Kopiëren
Kopieer de `lib/game/` en `lib/services/` folders uit dit project.

---

## Code Conventies

### Dart Style
- Gebruik `final` waar mogelijk
- Named parameters voor >2 args
- Extension methods voor enum display names
- Geen `!` null assertions - gebruik `??` of null checks

### State Management
- Game logic in pure Dart (geen Flutter imports)
- UI state in Riverpod providers
- Supabase calls alleen in service layer

### Testing
- Unit tests voor alle game logic
- Widget tests voor kritieke UI flows
- Geen mocks voor pure Dart classes

---

## Bekende Issues / Aandachtspunten

1. **Supabase Auth**: Anonieme users verlopen na 30 dagen - overweeg guest_id persistentie in SharedPreferences

2. **Optimistic Locking**: Bij concurrent modifications moet client opnieuw proberen - implementeer retry logic

3. **Card Images**: Nog geen assets - begin met Unicode symbolen (♠♥♦♣), later custom graphics

4. **Landscape Mode**: Kritiek voor speelbaarheid met veel kaarten - test vroeg op echte devices

5. **iOS Simulator**: Supabase realtime werkt soms niet goed - test op fysiek device

---

## Referenties

- [Supabase Flutter Docs](https://supabase.com/docs/reference/dart/introduction)
- [Riverpod Docs](https://riverpod.dev/)
- [Flutter Animate](https://pub.dev/packages/flutter_animate)
- Rapport: zie originele strategisch onderzoeksrapport voor marktanalyse en commercialisatie strategie

---

## Hulp Nodig?

Vraag Claude Code om:
- "Maak de lobby_screen.dart met realtime player list"
- "Implementeer de card_widget met animaties"
- "Voeg reconnect logic toe aan supabase_service"
- "Schrijf unit tests voor de bot logic"

De game logic is volledig getest - focus nu op de UI en multiplayer polish!
