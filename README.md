# Lekkerkaarten

Multiplayer Boerenbridge app - commerciele versie.

## Live

- **Productie**: [lekkerkaarten.nl](https://lekkerkaarten.nl)
- **Server**: 91.98.65.86 (Hetzner)
- **SSL**: Let's Encrypt (auto-renewal)

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
│       ├── home_banner.jpeg     # Homepagina achtergrond
│       └── logo.png             # Boerenbridge logo
│
├── web/
│   ├── index.html               # Meta tags, Open Graph
│   ├── manifest.json            # PWA configuratie
│   └── favicon.png              # Favicon (B icoon)
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

Deployment gaat automatisch via GitHub Actions bij push naar `main`.

```bash
# Handmatig deployen (indien nodig)
./deploy/deploy.sh

# Of handmatig
flutter build web --release
scp -r build/web/* root@91.98.65.86:/var/www/boerenbridge/
```

## Puntentelling

| Systeem | Goed geraden | Fout geraden |
|---------|--------------|--------------|
| **Basis** | 10 + (2 x slagen) | 0 punten |
| **Vlaams** | 10 + (3 x slagen) | 0 punten |
| **Nederlands** | 10 + (3 x slagen) | -(3 x verschil) |

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

### SSL

SSL is geconfigureerd met Let's Encrypt. Certificaat wordt automatisch vernieuwd.

```bash
# Handmatig vernieuwen (indien nodig)
certbot renew

# Status checken
certbot certificates
```

### Firewall (ufw)

Alleen essentiële poorten zijn open:

| Poort | Dienst |
|-------|--------|
| 22 | SSH |
| 80 | HTTP |
| 443 | HTTPS |

```bash
# Status bekijken
ufw status

# Firewall beheren
ufw allow <poort>/tcp
ufw deny <poort>/tcp
```

## Roadmap

### Te doen
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
- [x] Warm look & feel (beige styling)
- [x] Reconnect bij verloren verbinding
- [x] Bot overname (60s timeout, server tijd referentie)
- [x] DNS configuratie (lekkerkaarten.nl)
- [x] SSL certificaat (Let's Encrypt)
- [x] CI/CD pipeline (GitHub Actions)
- [x] Firewall (ufw)
- [x] Logo in AppBar
- [x] Favicon (B icoon)
- [x] Link preview / Open Graph tags

## Supabase

- **Project**: Boerenbridge
- **Region**: eu-central-1 (Frankfurt)
- **Dashboard**: https://supabase.com/dashboard

---

Lekkerkaarten - Alle rechten voorbehouden
