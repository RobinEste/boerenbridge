# Automatische Cleanup Setup

Deze guide helpt je de automatische cleanup van oude games in te stellen.

## Wat wordt opgeruimd?

Games die:
- Status `waiting` of `playing` hebben
- Ouder zijn dan **24 uur**

Bijbehorende data wordt ook verwijderd:
- `game_players`
- `game_state`
- `game_actions`

---

## Stap 1: Database functie installeren

1. Ga naar je Supabase project → **SQL Editor**
2. Kopieer en run de inhoud van: `migrations/20250126_cleanup_old_games.sql`

## Stap 2: Direct opruimen (eenmalig)

Run in de SQL Editor:

```sql
SELECT cleanup_old_games();
```

Je krijgt een JSON response met hoeveel er is verwijderd:
```json
{
  "deleted_games": 15,
  "deleted_players": 42,
  "deleted_states": 15,
  "deleted_actions": 230,
  "cleanup_time": "2025-01-26T12:00:00Z"
}
```

## Stap 3: Bekijk wat er opgeruimd gaat worden

```sql
SELECT * FROM old_games_overview;
```

---

## Automatische scheduling

### Optie A: Supabase Cron (Pro plan)

Als je Supabase Pro hebt, uncomment deze regels in de migration:

```sql
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule(
  'cleanup-old-games',
  '0 3 * * *',  -- Elke dag om 03:00 UTC
  'SELECT cleanup_old_games()'
);
```

### Optie B: Edge Function + externe cron (Free plan)

1. **Deploy de Edge Function:**
   ```bash
   supabase functions deploy cleanup-games
   ```

2. **Gebruik een gratis cron service** zoals [cron-job.org](https://cron-job.org):
   - URL: `https://<project-ref>.supabase.co/functions/v1/cleanup-games`
   - Method: POST
   - Headers:
     - `Authorization: Bearer <SUPABASE_ANON_KEY>`
   - Schedule: Dagelijks om 03:00

### Optie C: GitHub Actions (gratis)

Maak `.github/workflows/cleanup.yml`:

```yaml
name: Database Cleanup

on:
  schedule:
    - cron: '0 3 * * *'  # Dagelijks om 03:00 UTC
  workflow_dispatch:  # Handmatig triggeren

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger cleanup
        run: |
          curl -X POST \
            'https://${{ secrets.SUPABASE_PROJECT_REF }}.supabase.co/functions/v1/cleanup-games' \
            -H 'Authorization: Bearer ${{ secrets.SUPABASE_ANON_KEY }}'
```

Voeg secrets toe aan je GitHub repo:
- `SUPABASE_PROJECT_REF`: je project reference (bijv. `kjepglhqigvpvgbxlzaq`)
- `SUPABASE_ANON_KEY`: je anon/public key

---

## Handmatig cleanup draaien

### Via SQL Editor:
```sql
SELECT cleanup_old_games();
```

### Via Edge Function (als gedeployed):
```bash
curl -X POST \
  'https://<project-ref>.supabase.co/functions/v1/cleanup-games' \
  -H 'Authorization: Bearer <SUPABASE_ANON_KEY>'
```

---

## Monitoring

Bekijk hoeveel oude games er zijn:

```sql
SELECT
  cleanup_status,
  COUNT(*) as count,
  MIN(created_at) as oldest,
  MAX(created_at) as newest
FROM old_games_overview
GROUP BY cleanup_status;
```

---

## Cleanup interval aanpassen

Wil je games langer bewaren? Pas de interval aan in de functie:

```sql
-- Van 24 uur naar 7 dagen:
AND created_at < NOW() - INTERVAL '7 days'
```
