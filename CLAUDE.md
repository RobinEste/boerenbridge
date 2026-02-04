# Project Instructies - Lekkerkaarten (Boerenbridge)

## Git Remotes

| Remote | Repo | Gebruik |
|--------|------|---------|
| `private` | `RobinEste/lekkerkaarten` | **Actieve repo** — alle pushes, PRs en deploys gaan hierheen |
| `origin` | `RobinEste/boerenbridge` | **Publieke repo** — NIET naar pushen, laten zoals het is |

### Regels
- Push **alleen** naar `private` (lekkerkaarten)
- Maak PRs **alleen** aan op `private` (lekkerkaarten)
- Push **nooit** naar `origin` (boerenbridge) tenzij de gebruiker dit expliciet bevestigt

## Supabase

- **Project ref:** `kjepglhqigvpvgbxlzaq`
- **Authenticatie:** Anonieme login (`signInAnonymously()`) — spelers kiezen een naam en worden automatisch anoniem ingelogd
- **Supabase CLI:** Gelinkt vanuit `~/Projects/boerenbridge` (kleine b). Deploy Edge Functions vanuit die directory.

### Edge Functions

| Functie | Pad | Beschrijving |
|---------|-----|--------------|
| `cleanup-games` | `supabase/functions/cleanup-games/` | Verwijdert games ouder dan 24 uur |
| `security-scanner` | `supabase/functions/security-scanner/` | Scant database op 12+ security vulnerabilities |

Deploy: `cd ~/Projects/boerenbridge && supabase functions deploy <functie-naam>`

### Security Agent

Automatische security pipeline in `supabase/supabase-security-agent/`:

- **Edge Function** (`security-scanner`) scant dagelijks om 06:00 UTC via GitHub Actions
- **GitHub Issues** worden automatisch aangemaakt bij findings (met deduplicatie)
- **Claude Agent** (Python) analyseert issues en maakt PRs met fixes
- **Sentry** error tracking via Envelope API (geen SDK, Deno 1.x compatible). Actief wanneer `SENTRY_DSN` is gezet. Transactions/spans zijn no-ops.

Relevante bestanden:
- `.github/workflows/security-agent.yml` — GitHub Actions workflow
- `supabase/migrations/004_security_scanner_setup.sql` — Database setup (_security schema, exec_sql functie)
- `supabase/migrations/005_security_fixes.sql` — RLS, search_path en FK index fixes
- `supabase/supabase-security-agent/security_agent/` — Python agent code
- `supabase/supabase-security-agent/requirements.txt` — Python dependencies

### Geaccepteerde security findings

Deze findings zijn by design en uitgesloten van de scanner:
- `permissive_rls_policy` — games/game_players moeten zichtbaar zijn voor alle authenticated spelers
- `realtime_all_tables` — multiplayer kaartspel vereist realtime op game-tabellen

### GitHub Secrets (private repo)

| Secret | Beschrijving |
|--------|-------------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key |
| `ANTHROPIC_API_KEY` | Claude API key (voor security agent) |
| `SENTRY_DSN` | Sentry DSN (EU, `*.ingest.de.sentry.io`) — ook als Supabase secret |

## Sessie Management

Dit project gebruikt een werklog (`.claude/worklog.md`) om context tussen sessies te bewaren.

### Werklog discipline
- **Begin sessie:** Gebruik `/sessie-start` om context te laden
- **Tijdens sessie:** Werklog wordt automatisch bijgewerkt via `/sessie-eind`
- **Einde sessie:** Gebruik `/sessie-eind` om af te sluiten en werklog bij te werken
- **Tussendoor:** Gebruik `/status` voor een snel overzicht

### Regels
- De werklog bevat maximaal 5 sessie-historie rijen (oudste wordt verwijderd)
- Werklog wordt **alleen** bijgewerkt via `/sessie-eind`, niet handmatig
- Bij onverwachte afsluiting: begin volgende sessie gewoon met `/sessie-start`

## Slash Commands

| Command | Beschrijving | Wanneer |
|---------|-------------|---------|
| `/sessie-start` | Laadt werklog, roadmap, git status | Begin van een sessie |
| `/sessie-eind` | Checklist, tests, werklog bijwerken | Einde van een sessie |
| `/status` | Compact overzicht taak + git | Tussendoor |

### Voorbeelden
```
/sessie-start          → Laadt context, toont samenvatting, vraagt wat je wilt doen
/status                → Snel overzicht: taak + git status
/sessie-eind           → Checklist doorlopen, werklog bijwerken, push-herinnering
```
