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
- **Sentry** is voorbereid maar nog niet actief (stub in `sentry.ts`)

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
| `SENTRY_DSN` | Sentry DSN (optioneel, nog niet actief) |
