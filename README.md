# Lekkerkaarten

Multiplayer Boerenbridge app - commerciele versie.

## Live

- **Productie**: [lekkerkaarten.nl](http://lekkerkaarten.nl)
- **Server**: 91.98.65.86 (Hetzner)

## Tech Stack

| Component | Technologie |
|-----------|-------------|
| Frontend | Flutter (Web, iOS, Android) |
| Backend | Supabase (Realtime, PostgreSQL) |
| State | Riverpod |
| Routing | GoRouter |
| Auth | Supabase Auth (anoniem) |
| Hosting | Hetzner + Nginx |

## Project Structuur

```
lekkerkaarten/
├── lib/
│   ├── game/                    # Core game logic (pure Dart)
│   │   ├── models.dart          # Card, Player, Trick, PlayedCard classes
│   │   ├── rules.dart           # GameRules, ScoringSystem enum
│   │   └── game_state.dart      # GameState, GamePhase enum
│   │
│   ├── services/
│   │   └── supabase_service.dart # Supabase CRUD en realtime subscriptions
│   │
│   ├── providers/
│   │   ├── game_provider.dart   # Game state management
│   │   ├── lobby_provider.dart  # Lobby/join logic
│   │   └── auth_provider.dart   # Anonieme auth + naam opslag
│   │
│   ├── screens/
│   │   ├── home_screen.dart     # Startscherm (naam, code invoer)
│   │   ├── lobby_screen.dart    # Wachtruimte voor spelers
│   │   └── game_screen.dart     # Hoofdscherm tijdens spel
│   │
│   ├── widgets/
│   │   ├── playing_card.dart    # Speelkaart widget
│   │   ├── player_hand.dart     # Hand met kaarten
│   │   ├── score_board.dart     # Scorebord
│   │   └── trick_area.dart      # Huidige slag weergave
│   │
│   ├── config.dart              # Supabase credentials (NIET in git!)
│   └── main.dart                # App entry point + routing
│
├── supabase/
│   └── schema.sql               # Database schema
│
├── assets/
│   └── images/
│       └── home_banner.jpeg     # Homepagina achtergrond
│
├── test/                        # 118 unit tests
│   └── game/
│       ├── game_state_test.dart
│       ├── rules_test.dart
│       └── models_test.dart
│
├── bb-aan                       # Start script (flutter run -d chrome)
├── bb-uit                       # Stop script
└── pubspec.yaml
```

## Development

### Starten

```bash
./bb-aan                    # Of: flutter run -d chrome
```

### Stoppen

```bash
./bb-uit
```

### Tests

```bash
flutter test                # Alle tests (118)
flutter test test/game/     # Alleen game logic
```

### Build & Deploy

```bash
# Build
flutter build web --release

# Deploy naar server
scp -r build/web/* root@91.98.65.86:/var/www/boerenbridge/
```

## Puntentelling

| Systeem | Goed geraden | Fout geraden |
|---------|--------------|--------------|
| **Basis** | 10 + (2 x slagen) | 0 punten |
| **Vlaams** | 5 + slagen | 0 punten |
| **Nederlands** | 10 + (2 x slagen) | -(2 x verschil) |

## Server Configuratie

### SSH Toegang

```bash
ssh root@91.98.65.86
```

### Nginx Config

Locatie: `/etc/nginx/sites-available/boerenbridge`

```nginx
server {
    listen 80;
    server_name lekkerkaarten.nl www.lekkerkaarten.nl _;
    root /var/www/boerenbridge;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

### SSL (nog te doen)

```bash
apt install certbot python3-certbot-nginx -y
certbot --nginx -d lekkerkaarten.nl -d www.lekkerkaarten.nl
```

## Roadmap

### Te doen

- [ ] DNS instellen bij Webreus
- [ ] SSL certificaat installeren
- [ ] Reconnect bij verloren verbinding
- [ ] Bot overname bij disconnect
- [ ] Sound effects
- [ ] Statistieken en geschiedenis
- [ ] Push notifications
- [ ] Native iOS/Android builds
- [ ] App Store / Play Store publicatie

### Voltooid

- [x] Core game logic met tests
- [x] Multiplayer via Supabase realtime
- [x] 3 scoring systemen
- [x] Configureerbaar aantal rondes
- [x] Bid summary overlay
- [x] Trick result overlay
- [x] Home screen met achtergrond
- [x] Hetzner server deployment

## Supabase

- **Project**: Boerenbridge
- **Region**: eu-central-1 (Frankfurt)
- **Dashboard**: https://supabase.com/dashboard

---

Lekkerkaarten - Alle rechten voorbehouden
