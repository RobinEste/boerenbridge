# Boerenbridge

Een Nederlandse multiplayer Boerenbridge app gebouwd met Flutter en Supabase.

**Dit is een volledig werkende basisversie die iedereen mag forken en verder doorontwikkelen!**

## Features

- Multiplayer via 4-letter spelcode (bijv. "ABCD")
- Realtime synchronisatie tussen spelers
- 3 puntentellingsystemen: Basis, Vlaams, Nederlands
- Configureerbaar aantal rondes
- Visuele overlays voor biedoverzicht en slagresultaten
- Responsive design voor web en mobiel

## Demo

Zelf op te zetten.

## Tech Stack

| Component | Technologie |
|-----------|-------------|
| Frontend | Flutter (Web, iOS, Android) |
| Backend | Supabase (Realtime, PostgreSQL) |
| State | Riverpod |
| Routing | GoRouter |
| Auth | Supabase Auth (anoniem) |

## Project Structuur

```
boerenbridge/
├── lib/
│   ├── game/                    # Core game logic (pure Dart)
│   │   ├── models.dart          # Card, Player, Trick classes
│   │   ├── rules.dart           # Spelregels en puntentelling
│   │   └── game_state.dart      # State machine voor spelverloop
│   │
│   ├── services/
│   │   └── supabase_service.dart # Supabase integratie
│   │
│   ├── providers/               # Riverpod state management
│   │   ├── game_provider.dart
│   │   ├── lobby_provider.dart
│   │   └── auth_provider.dart
│   │
│   ├── screens/
│   │   ├── home_screen.dart     # Startscherm met spelcode invoer
│   │   ├── lobby_screen.dart    # Wachtruimte voor spelers
│   │   └── game_screen.dart     # Speelscherm met kaarten
│   │
│   ├── widgets/                 # Herbruikbare UI componenten
│   │   ├── playing_card.dart
│   │   ├── player_hand.dart
│   │   └── score_board.dart
│   │
│   └── main.dart
│
├── supabase/
│   └── schema.sql               # Database schema
│
├── assets/
│   └── images/                  # Afbeeldingen
│
├── test/                        # 118 unit tests
│
└── pubspec.yaml
```

## Quick Start

### 1. Prerequisites

- Flutter SDK (https://docs.flutter.dev/get-started/install)
- Een Supabase account (gratis tier is voldoende)

### 2. Supabase Opzetten

1. Maak een project op [supabase.com](https://supabase.com)
2. Voer `supabase/schema.sql` uit in de SQL Editor
3. Kopieer je Project URL en anon key van Settings > API

### 3. Configuratie

Maak `lib/config.dart`:

```dart
class Config {
  static const supabaseUrl = 'https://YOUR_PROJECT.supabase.co';
  static const supabaseAnonKey = 'YOUR_ANON_KEY';
}
```

> Voeg `lib/config.dart` toe aan `.gitignore`!

### 4. Installeren en Starten

```bash
flutter pub get
flutter run -d chrome
```

## Puntentelling

De app ondersteunt 3 systemen:

| Systeem | Goed geraden | Fout geraden |
|---------|--------------|--------------|
| **Basis** | 10 + (2 x slagen) | 0 punten |
| **Vlaams** | 10 + (3 x slagen) | 0 punten |
| **Nederlands** | 10 + (3 x slagen) | -(3 x verschil) |

## Testing

```bash
# Alle tests uitvoeren
flutter test

# Specifieke test groep
flutter test test/game/
```

## Deployment

### Flutter Web Build

```bash
flutter build web --release
```

De build staat in `build/web/` en kan naar elke webserver.

### Nginx Voorbeeld

```nginx
server {
    listen 80;
    server_name jouwdomein.nl;
    root /var/www/boerenbridge;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

## Doorontwikkelen

Dit project is bedoeld als basis. Ideeen voor uitbreidingen:

- [ ] Reconnect bij verloren verbinding
- [ ] Bot overname bij disconnect
- [ ] Sound effects
- [ ] Statistieken en geschiedenis
- [ ] Push notifications
- [ ] Native iOS/Android apps
- [ ] Toernooien modus
- [ ] Custom thema's

## Contributing

1. Fork de repo
2. Maak een feature branch (`git checkout -b feature/jouw-feature`)
3. Commit je changes
4. Push en open een Pull Request

## License

MIT License - vrij te gebruiken en aan te passen.

---

Gebouwd met Flutter, Supabase en Claude Code
