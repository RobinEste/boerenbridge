# 🃏 Boerenbridge

Een Nederlandse multiplayer Boerenbridge app gebouwd met Flutter en Supabase.

## Tech Stack

| Component | Technologie | Waarom |
|-----------|-------------|--------|
| Frontend | Flutter | Cross-platform (iOS, Android, Web) met native performance |
| Backend | Supabase | Gratis tier, ingebouwde Realtime, PostgreSQL |
| State | Riverpod | Type-safe, testbaar, async support |
| Auth | Supabase Auth | Anonieme accounts voor guests |

## Project Structuur

```
boerenbridge/
├── lib/
│   ├── game/                    # Core game logic (pure Dart, geen dependencies)
│   │   ├── models.dart          # Card, Player, Trick classes
│   │   ├── rules.dart           # Configureerbare spelregels
│   │   └── game_state.dart      # State machine voor spelverloop
│   │
│   ├── services/
│   │   └── supabase_service.dart # Supabase integratie
│   │
│   ├── providers/               # Riverpod providers (nog aan te maken)
│   │   ├── game_provider.dart
│   │   └── auth_provider.dart
│   │
│   ├── screens/                 # UI schermen (nog aan te maken)
│   │   ├── home_screen.dart
│   │   ├── lobby_screen.dart
│   │   └── game_screen.dart
│   │
│   ├── widgets/                 # Herbruikbare widgets (nog aan te maken)
│   │   ├── card_widget.dart
│   │   ├── hand_widget.dart
│   │   └── trick_widget.dart
│   │
│   └── main.dart
│
├── supabase/
│   └── schema.sql               # Database schema
│
├── test/
│   └── game/                    # Unit tests voor game logic
│
└── pubspec.yaml
```

## Quick Start

### 1. Prerequisites

```bash
# Flutter installeren (als je dit nog niet hebt)
# Zie: https://docs.flutter.dev/get-started/install

# Supabase CLI (optioneel, voor lokale development)
brew install supabase/tap/supabase
```

### 2. Supabase Project Opzetten

1. Ga naar [supabase.com](https://supabase.com) en maak een gratis account
2. Maak een nieuw project aan
3. Ga naar **SQL Editor** en voer `supabase/schema.sql` uit
4. Ga naar **Settings > API** en kopieer:
   - Project URL
   - anon/public key

### 3. Flutter Project Initialiseren

```bash
# Maak Flutter project (of clone deze repo)
flutter create --org nl.jouwbedrijf boerenbridge
cd boerenbridge

# Voeg dependencies toe aan pubspec.yaml
flutter pub add supabase_flutter
flutter pub add flutter_riverpod
flutter pub add go_router

# Kopieer de game logic bestanden naar lib/
```

### 4. Configuratie

Maak `lib/config.dart`:

```dart
class Config {
  static const supabaseUrl = 'https://YOUR_PROJECT.supabase.co';
  static const supabaseAnonKey = 'YOUR_ANON_KEY';
}
```

> ⚠️ **Let op:** Voeg `lib/config.dart` toe aan `.gitignore`!

### 5. Run

```bash
flutter run
```

## Game Logic Overzicht

### Configureerbare Regels

De app ondersteunt diverse regelvarianten:

```dart
// Standaard Nederlands
final rules = GameRules.dutch;

// Vlaamse variant (andere puntentelling)
final rules = GameRules.flemish;

// Custom regels
final rules = GameRules(
  scoringSystem: ScoringSystem.withPenalty,
  roundSequence: RoundSequence.ascending,
  screwTheDealer: true,
  zeroBidBonus: 5,
);
```

### State Machine Fases

```
LOBBY → BIDDING → PLAYING → ROUND_END → (herhaal of) GAME_END
         ↑___________|
```

### Multiplayer Flow

1. **Host maakt spel** → krijgt 4-letter code (bijv. "ABCD")
2. **Vrienden joinen** → voeren code in
3. **Host start spel** → kaarten worden gedeeld
4. **Realtime sync** → alle acties worden direct naar alle spelers gepusht

## Development Roadmap

### Fase 1: MVP (Week 1-2)
- [x] Game logic in pure Dart
- [x] Supabase schema
- [x] Supabase service layer
- [ ] Basis UI (lobby + spel scherm)
- [ ] Kaart animaties

### Fase 2: Polish (Week 3-4)
- [ ] Reconnect logic (bij verloren verbinding)
- [ ] Bot overname bij disconnect
- [ ] Sound effects
- [ ] Statistieken scherm

### Fase 3: Commercieel (Week 5+)
- [ ] Premium features (custom regels)
- [ ] Remove ads voor premium
- [ ] In-app purchase integratie
- [ ] App Store / Play Store publicatie

## Testing

```bash
# Unit tests voor game logic
flutter test test/game/

# Integration tests
flutter test integration_test/
```

### Voorbeeld test:

```dart
void main() {
  group('Boerenbridge Rules', () {
    test('Screw the dealer prevents exact total', () {
      final rules = GameRules.dutch;
      
      // 5 kaarten, 3 al geboden → deler mag geen 2 bieden
      final allowed = rules.allowedBidsForDealer(5, 3);
      
      expect(allowed, isNot(contains(2)));
      expect(allowed, contains(0));
      expect(allowed, contains(1));
      expect(allowed, contains(3));
    });
    
    test('Standard scoring: correct bid', () {
      final rules = GameRules.dutch;
      
      // Bod 3, gehaald 3 → 10 + 6 = 16 punten
      final score = rules.calculateRoundScore(3, 3);
      
      expect(score, equals(16));
    });
  });
}
```

## Contributing

1. Fork de repo
2. Maak een feature branch (`git checkout -b feature/amazing-feature`)
3. Commit je changes (`git commit -m 'Add amazing feature'`)
4. Push naar de branch (`git push origin feature/amazing-feature`)
5. Open een Pull Request

## License

MIT License - zie [LICENSE](LICENSE) voor details.

---

Gebouwd met ❤️ en Claude Code
