# Handleiding: Supabase Security Vulnerability Agent

Een complete gids voor het opzetten van een geautomatiseerde security scanning pipeline voor Supabase projecten. Gebaseerd op de implementatie voor Lekkerkaarten (Boerenbridge).

---

## Inhoudsopgave

1. [Overzicht](#overzicht)
2. [Vereisten](#vereisten)
3. [Fase 1: Database migratie](#fase-1-database-migratie)
4. [Fase 2: Edge Function](#fase-2-edge-function)
5. [Fase 3: GitHub Actions](#fase-3-github-actions)
6. [Fase 4: Claude Agent (Python)](#fase-4-claude-agent-python)
7. [Fase 5: Sentry EU](#fase-5-sentry-eu)
8. [Configuratie en tuning](#configuratie-en-tuning)
9. [Testen](#testen)
10. [Lessen en valkuilen](#lessen-en-valkuilen)

---

## Overzicht

De pipeline werkt als volgt:

```
Supabase DB ──→ Edge Function Scanner ──→ GitHub Issues ──→ GitHub Action ──→ Claude Agent ──→ Pull Request
  (dagelijks)     (12+ SQL checks)        (met dedup)       (triggered)      (analyseert)     (met fix)
```

### Componenten

| Component | Technologie | Locatie |
|-----------|-------------|---------|
| Security Scanner | TypeScript (Deno Edge Function) | `supabase/functions/security-scanner/` |
| Scheduler | GitHub Actions (cron) | `.github/workflows/security-agent.yml` |
| Security Agent | Python + Claude API | `supabase/supabase-security-agent/security_agent/` |
| Database | PostgreSQL (`_security` schema) | `supabase/migrations/004_security_scanner_setup.sql` |
| Monitoring | Sentry EU (Frankfurt) | Envelope API in `sentry.ts`, Python SDK in agent |

### Wat wordt gescand (12+ checks)

| Check | Severity | Categorie |
|-------|----------|-----------|
| RLS uitgeschakeld op public tabellen | High | RLS |
| RLS aan maar geen policies | High | RLS |
| Te permissieve RLS policies | Medium | RLS |
| Auth users tabel exposed | Critical | Authenticatie |
| Zwak wachtwoordbeleid | Medium | Authenticatie |
| Gevoelige kolommen in public schema | High | Data exposure |
| Materialized views exposed | Medium | Data exposure |
| Extensions in public schema | Medium | Extensions |
| Security definer views | Medium | Autorisatie |
| Functions zonder vaste search_path | Medium | Configuratie |
| Unindexed foreign keys | Low | Performance |
| Public storage buckets | High | Autorisatie |
| Storage objects zonder RLS | High | RLS |
| Realtime op gevoelige tabellen | Medium | Data exposure |

---

## Vereisten

### Accounts en tools

- **Supabase project** (Free plan werkt, geen pg_cron nodig)
- **GitHub repository** (private aanbevolen)
- **Supabase CLI** (`brew install supabase/tap/supabase`)
- **GitHub Personal Access Token** (scope: `repo`)
- **Anthropic API key** (voor Claude agent)
- **Sentry EU project** (aanbevolen — Frankfurt data residency)

### Supabase CLI installeren en linken

```bash
# Installeren
brew install supabase/tap/supabase

# Inloggen (druk Enter, browser opent)
supabase login

# Linken aan project
supabase link --project-ref <jouw-project-ref>
```

> **Let op:** De project ref vind je in de Supabase Dashboard URL:
> `https://supabase.com/dashboard/project/<project-ref>`

> **Valkuil:** Onthoud vanuit welke directory je `supabase link` uitvoert.
> De CLI slaat de configuratie lokaal op. Alle toekomstige `supabase` commando's
> moeten vanuit dezelfde directory worden uitgevoerd.

### GitHub Personal Access Token aanmaken

1. GitHub → profielfoto → **Settings**
2. Scroll naar beneden → **Developer settings**
3. **Personal access tokens** → **Tokens (classic)**
4. **Generate new token (classic)**
5. Scope: `repo` (dat is voldoende)
6. Expiration: 90 dagen (je krijgt een reminder e-mail)
7. Kopieer de token meteen — je ziet hem maar één keer

---

## Fase 1: Database migratie

### Wat wordt aangemaakt

- `_security` schema — gescheiden van je applicatie data
- `_security.scans` tabel — slaat scan resultaten op
- `_security.exec_sql()` functie — voert SQL queries uit (SECURITY DEFINER)
- `public.exec_sql()` wrapper — checkt op service_role JWT
- `_security.latest_scan` view — laatste scan resultaat
- `_security.get_rls_status()` — RLS status helper

### Toepassen

Kopieer de inhoud van `supabase/migrations/004_security_scanner_setup.sql` en voer het uit in de **Supabase SQL Editor** (Dashboard → SQL Editor).

### Belangrijke security overwegingen

De `exec_sql()` functie kan elke SQL query uitvoeren. Dit is by design voor de scanner, maar:

- De functie is alleen toegankelijk via `service_role` JWT
- De `public.exec_sql()` wrapper checkt expliciet op `service_role` in de JWT claims
- `anon` en `authenticated` rollen hebben geen directe toegang
- De `service_role` key moet goed beschermd worden (alleen in GitHub Secrets en Supabase Secrets)

```sql
-- De wrapper checkt dit:
IF current_setting('request.jwt.claims', true)::jsonb->>'role' != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: requires service_role';
END IF;
```

---

## Fase 2: Edge Function

### Bestanden

```
supabase/functions/security-scanner/
├── index.ts      # Hoofd Edge Function (request handler + scan logica)
├── checks.ts     # Alle security check definities met SQL queries
├── types.ts      # TypeScript type definities
└── sentry.ts     # Sentry integratie via Envelope API (geen SDK)
```

### Belangrijke technische details

**Gebruik `Deno.serve` in plaats van `serve` import:**

```typescript
// FOUT — verouderd, werkt niet meer
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
serve(async (req) => { ... });

// GOED — moderne Supabase Edge Function
Deno.serve(async (req: Request) => { ... });
```

**Gebruik losse versie voor supabase-js:**

```typescript
// FOUT — specifieke patch versie kan problemen geven
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

// GOED — major versie is voldoende
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
```

**Sentry via Envelope API (geen SDK):**

`@sentry/deno` vereist Deno 2, maar Supabase draait Deno 1.45.2. De `sentry.ts`
module gebruikt de Sentry Envelope API (HTTP POST) voor error capture. Transactions
en spans zijn no-ops. Zonder `SENTRY_DSN` zijn alle functies automatisch no-ops.

### Deduplicatie

De scanner checkt bestaande open GitHub issues voordat er nieuwe worden aangemaakt.
Dit voorkomt dat dezelfde vulnerability elke dag een nieuw issue genereert.

```typescript
// Haal bestaande open issues op
const existingIssues = await getExistingIssues(token, owner, repo);

// Skip als er al een open issue is voor deze check
if (existingIssues.has(vuln.check_name)) {
  console.log(`Skipping duplicate issue for: ${vuln.check_name}`);
  continue;
}
```

### Deployen

```bash
# Vanuit de directory waar supabase link is uitgevoerd
supabase functions deploy security-scanner
```

### Secrets instellen

```bash
supabase secrets set GITHUB_TOKEN=<token> GITHUB_OWNER=<owner> GITHUB_REPO=<repo>
```

De Edge Function gebruikt ook automatisch `SUPABASE_URL` en `SUPABASE_SERVICE_ROLE_KEY`
die Supabase zelf injecteert.

### Endpoints

| Methode | Pad | Beschrijving |
|---------|-----|--------------|
| POST | `/security-scanner` | Voer volledige scan uit |
| POST | `/security-scanner/check` | Voer specifieke check uit (`{"check_id": "rls_disabled_in_public"}`) |
| GET | `/security-scanner/status` | Laatste scan resultaat ophalen |

---

## Fase 3: GitHub Actions

### Workflow bestand

Locatie: `.github/workflows/security-agent.yml`

### Triggers

| Trigger | Wanneer | Wat |
|---------|---------|-----|
| `schedule` | Dagelijks 06:00 UTC | Triggert de Edge Function scan |
| `issues` | Nieuw issue met `security` label | Start de Claude agent |
| `workflow_dispatch` | Handmatig via GitHub UI | Triggert de scan |

### Jobs

**Job 1: `scan`**
- Roept de Edge Function aan via curl
- Gebruikt `SUPABASE_URL` en `SUPABASE_SERVICE_ROLE_KEY` secrets
- Logt de resultaten en geeft een warning bij critical/high findings

**Job 2: `process-issue`**
- Draait alleen bij nieuwe issues met het `security` label
- Skipt issues die al `security-agent-processed` label hebben
- Installeert Python dependencies
- Draait de Claude agent op het specifieke issue

### GitHub Secrets instellen

Ga naar de repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

| Secret | Beschrijving | Verplicht |
|--------|-------------|-----------|
| `SUPABASE_URL` | Supabase project URL | Ja |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key (Dashboard → Settings → API) | Ja |
| `ANTHROPIC_API_KEY` | Claude API key | Ja (voor agent) |
| `SENTRY_DSN` | Sentry EU DSN (`*.ingest.de.sentry.io`) | Nee (aanbevolen) |

> **Let op:** `GITHUB_TOKEN` wordt automatisch door GitHub Actions aangeleverd.
> De `GITHUB_TOKEN` in Supabase Secrets (voor de Edge Function) moet je wel handmatig
> instellen — dit is de Personal Access Token die je hebt aangemaakt.

### Handmatig triggeren

GitHub → repo → **Actions** tab → **Security Agent** → **Run workflow**

---

## Fase 4: Claude Agent (Python)

### Bestanden

```
supabase/supabase-security-agent/
├── requirements.txt              # Dependencies: anthropic, PyGithub, sentry-sdk
├── security_agent/
│   ├── __init__.py               # Package init (importeert main_with_sentry)
│   ├── main.py                   # Agent zonder Sentry
│   ├── main_with_sentry.py       # Agent met Sentry integratie
│   └── sentry_integration.py     # Python Sentry helper module
```

### Hoe de agent werkt

1. Ontvangt een GitHub issue nummer
2. Parset de vulnerability details uit de issue body (severity, affected objects, remediation hints)
3. Stuurt de informatie naar Claude met een system prompt als database security engineer
4. Claude genereert: analyse, migratie SQL, rollback SQL, test SQL, risicobeoordeling
5. Agent maakt een branch en PR aan met de migratie bestanden
6. Issue krijgt het `security-agent-processed` label

### Dependencies

```
anthropic>=0.40.0
PyGithub>=2.1.0
sentry-sdk>=2.0.0
```

### __init__.py

Als je Sentry wilt gebruiken, importeer vanuit `main_with_sentry`:

```python
from .main_with_sentry import SecurityAgent, AgentConfig, Vulnerability, SecurityFix
```

Zonder Sentry, importeer vanuit `main`:

```python
from .main import SecurityAgent, AgentConfig, Vulnerability, SecurityFix
```

---

## Fase 5: Sentry EU

Sentry is actief met EU data residency (Frankfurt). Alle data wordt opgeslagen
in de EU. Als `SENTRY_DSN` niet is ingesteld, zijn alle functies no-ops —
de scanner werkt dan gewoon zonder monitoring.

### Architectuur

De `@sentry/deno` SDK vereist Deno 2, maar Supabase Edge Functions draaien op
Deno 1.45.2. Daarom wordt een hybride aanpak gebruikt:

| Component | Methode | Wat wordt getracked |
|-----------|---------|---------------------|
| Edge Function | Envelope API (HTTP POST, geen SDK) | Errors, vulnerability events, breadcrumbs |
| Python Agent | Standaard `sentry-sdk` | LLM calls, GitHub operaties, errors |

**Transactions en spans** zijn no-ops in de Edge Function — performance monitoring
vereist de SDK en is niet mogelijk zonder Deno 2 support.

### Wat de Edge Function tracked

- **Errors** (`captureError`, `captureGitHubError`) — volledige stack trace, breadcrumbs, context
- **Vulnerability events** (`recordVulnerability`) — als warning-level message events
- **Breadcrumbs** — in-memory buffer (max 50), meegezonden bij errors
- **Context/tags** — scan ID, project ref, check resultaten
- **Scan metrics** — als breadcrumb (geen echte Sentry metrics zonder SDK)

### Data sanitization

Gevoelige data wordt automatisch verwijderd uit events:
- JWT tokens (`eyJ...`)
- API keys (`sk-*`, `ghp_*`, `sk-ant-*`, `sbp_*`)
- Wachtwoorden in connection strings

### Graceful degradation

- Zonder `SENTRY_DSN` → alle functies zijn no-ops, scanner werkt normaal
- Ongeldige DSN → warning in console, verder als no-op
- Sentry onbereikbaar → fire-and-forget, scan loopt door
- `flushSentry()` → max 2 seconden timeout via `Promise.race()`

### Secrets instellen

```bash
# Supabase (voor Edge Function)
supabase secrets set SENTRY_DSN=<dsn> SENTRY_ENVIRONMENT=production

# GitHub (voor Python agent)
# Repo → Settings → Secrets → New: SENTRY_DSN
```

> **Let op:** De DSN moet naar `*.ingest.de.sentry.io` wijzen (EU endpoint).
> Maak het Sentry project aan met EU data residency (Frankfurt).

### Python Agent

De Python agent heeft volledige Sentry ondersteuning via `sentry_integration.py`.
De GitHub Actions workflow geeft `SENTRY_DSN` automatisch door. De agent tracked:
- LLM calls (tokens, duur)
- GitHub operaties
- Vulnerability events
- Errors met context

---

## Configuratie en tuning

### Checks excluden

In `index.ts` kun je checks excluden die by design zijn voor jouw project:

```typescript
const DEFAULT_CONFIG: ScannerConfig = {
  enabled_checks: 'all',
  excluded_checks: [
    'permissive_rls_policy',  // By design: tabellen moeten zichtbaar zijn
    'realtime_all_tables',    // By design: multiplayer spel vereist realtime
  ],
  // ...
};
```

Na wijzigingen opnieuw deployen:

```bash
supabase functions deploy security-scanner
```

### Severity threshold aanpassen

```typescript
const DEFAULT_CONFIG: ScannerConfig = {
  severity_threshold: 'medium',  // Negeert 'low' en 'info' findings
  // ...
};
```

### Tabellen en schema's excluden

```typescript
const DEFAULT_CONFIG: ScannerConfig = {
  excluded_tables: ['_prisma_migrations', 'schema_migrations', 'mijn_temp_tabel'],
  excluded_schemas: ['pg_catalog', 'information_schema', 'pg_toast'],
  // ...
};
```

### Nieuwe checks toevoegen

Voeg een nieuw object toe aan de `SECURITY_CHECKS` array in `checks.ts`:

```typescript
{
  id: 'mijn_custom_check',
  name: 'Mijn Custom Check',
  description: 'Beschrijving van wat er gecontroleerd wordt.',
  severity: 'high',
  category: 'rls',
  query: `
    SELECT schemaname, tablename, 'Probleem beschrijving' as issue
    FROM pg_tables
    WHERE schemaname = 'public'
      AND <jouw conditie>
  `,
  remediation: `
    SQL om het probleem op te lossen:
    ALTER TABLE ...;
  `,
  documentation_url: 'https://...'
}
```

---

## Testen

### Edge Function handmatig testen

```bash
curl -s -X POST https://<project-ref>.supabase.co/functions/v1/security-scanner \
  -H "Authorization: Bearer <service-role-key>" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

> **Let op:** Plak het hele commando op één regel. Geen regeleinden in de JWT token.
> Geen `< >` hoekjes rond de token.

### Specifieke check testen

```bash
curl -s -X POST https://<project-ref>.supabase.co/functions/v1/security-scanner/check \
  -H "Authorization: Bearer <service-role-key>" \
  -H "Content-Type: application/json" \
  -d '{"check_id": "rls_disabled_in_public"}' | python3 -m json.tool
```

### Laatste scan status ophalen

```bash
curl -s https://<project-ref>.supabase.co/functions/v1/security-scanner/status \
  -H "Authorization: Bearer <service-role-key>" | python3 -m json.tool
```

### GitHub Actions handmatig triggeren

GitHub → repo → **Actions** tab → **Security Agent** → **Run workflow**

### Scan resultaten in database bekijken

```sql
SELECT * FROM _security.latest_scan;
```

Of alle scans:

```sql
SELECT scan_id, started_at, total_checks, passed_checks, failed_checks, summary
FROM _security.scans
ORDER BY created_at DESC
LIMIT 10;
```

---

## Lessen en valkuilen

### 1. Supabase CLI directory mismatch

**Probleem:** `supabase functions deploy` faalt met "Cannot find project ref".

**Oorzaak:** `supabase link` slaat configuratie lokaal op. Als je vanuit een andere
directory deployt, vindt de CLI de configuratie niet.

**Oplossing:** Deploy altijd vanuit dezelfde directory waar je `supabase link` hebt uitgevoerd.
Let ook op hoofd-/kleine letters in het pad (macOS is case-insensitive maar de CLI niet altijd).

### 2. Deno.serve vs serve import

**Probleem:** Edge Function deploy faalt met module not found errors.

**Oorzaak:** De verouderde `serve` import van `deno.land/std` werkt niet meer in
nieuwe Supabase Edge Runtime versies.

**Oplossing:** Gebruik `Deno.serve()` direct, zonder import. Kijk naar bestaande
werkende Edge Functions in je project als referentie.

### 3. Sentry SDK werkt niet op Deno 1.x

**Probleem:** `@sentry/deno` vereist Deno 2, maar Supabase Edge Functions draaien op Deno 1.45.2.

**Oplossing:** Hybride client die de Sentry Envelope API gebruikt (HTTP POST) voor
error capture en message events. Transactions/spans zijn no-ops. Dit geeft error
tracking met breadcrumbs en context, zonder SDK dependency.

### 4. JWT token op meerdere regels

**Probleem:** curl geeft "Invalid JWT" terug.

**Oorzaak:** De JWT token is over meerdere regels gesplitst waardoor er
onzichtbare spaties of newlines in zitten. Of de punten (`.`) tussen de drie JWT
delen ontbreken.

**Oplossing:** Plak het hele curl commando inclusief token op één regel.
Controleer dat de JWT drie delen heeft gescheiden door punten:
`<header>.<payload>.<signature>`

### 5. Duplicate GitHub issues

**Probleem:** De scanner maakt bij elke run nieuwe issues aan voor dezelfde findings.

**Oorzaak:** Geen deduplicatie — de scanner checkte niet of er al een open issue
bestond voor dezelfde vulnerability.

**Oplossing:** Deduplicatie-logica toegevoegd die bestaande open issues checkt
op titel match voordat er een nieuw issue wordt aangemaakt. Sluit oude duplicaten
in bulk:

```bash
gh issue list --repo <owner>/<repo> --state open --label "security,automated" \
  --limit 200 --json number --jq '.[].number' | \
  xargs -I {} gh issue close {} --repo <owner>/<repo> \
  --comment "Gesloten: findings opgelost of geaccepteerd."
```

### 6. Permissive RLS is niet altijd een probleem

**Probleem:** Scanner rapporteert `USING (true)` policies als vulnerability.

**Context:** Voor sommige tabellen is dit by design. In een multiplayer spel
moeten spelers alle games en medespelers kunnen zien.

**Oplossing:** Excludeer de check via `excluded_checks` config, of beperk
de policy van `public` (anon + authenticated) naar alleen `authenticated`:

```sql
-- Van: toegankelijk voor iedereen inclusief anoniem
CREATE POLICY "viewable" ON games FOR SELECT USING (true);

-- Naar: alleen voor ingelogde gebruikers
CREATE POLICY "viewable" ON games FOR SELECT TO authenticated USING (true);
```

### 7. Realtime uitzetten breekt multiplayer apps

**Probleem:** Scanner rapporteert realtime op tabellen als risico.

**Context:** Voor multiplayer/realtime apps is dit vereist.

**Oplossing:** Excludeer de `realtime_all_tables` check. Dit is een bewuste
keuze, geen security probleem.

### 8. Free plan heeft geen pg_cron

**Probleem:** Kan geen scheduled scans in Supabase zelf draaien.

**Oplossing:** Gebruik GitHub Actions als scheduler met `schedule: cron`.
Dit werkt op elk Supabase plan en is gratis voor public repos (en 2000 min/maand
voor private repos).

### 9. Anonieme authenticatie en RLS

**Probleem:** Onduidelijk of anonieme gebruikers `authenticated` zijn.

**Verduidelijking:** Supabase `signInAnonymously()` maakt een echte
authenticated sessie aan. Deze gebruikers vallen onder de `authenticated` rol,
niet onder `anon`. Policies met `TO authenticated` werken voor hen.

### 10. Security fixes migratie

Bij het fixen van gevonden vulnerabilities, maak altijd een aparte migratie:

```sql
-- Voorbeeld: 005_security_fixes.sql

-- 1. RLS policies beperken
DROP POLICY IF EXISTS "te brede policy" ON mijn_tabel;
CREATE POLICY "beperkte policy" ON mijn_tabel
    FOR SELECT TO authenticated USING (true);

-- 2. Search path vastleggen op SECURITY DEFINER functies
CREATE OR REPLACE FUNCTION mijn_functie()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public  -- DIT TOEVOEGEN
AS $$ ... $$;

-- 3. Foreign key indexes
CREATE INDEX IF NOT EXISTS idx_tabel_kolom ON tabel (kolom);
```

---

## Checklist nieuw project

Gebruik deze checklist bij het opzetten van de security agent op een nieuw project:

- [ ] Supabase CLI installeren (`brew install supabase/tap/supabase`)
- [ ] Supabase CLI linken (`supabase login` + `supabase link`)
- [ ] SQL migratie toepassen (004_security_scanner_setup.sql) via SQL Editor
- [ ] Edge Function bestanden kopiëren naar `supabase/functions/security-scanner/`
- [ ] `index.ts` checks reviewen: welke zijn relevant, welke excluden
- [ ] Edge Function deployen (`supabase functions deploy security-scanner`)
- [ ] Supabase secrets instellen (`GITHUB_TOKEN`, `GITHUB_OWNER`, `GITHUB_REPO`)
- [ ] GitHub Personal Access Token aanmaken (scope: `repo`, 90 dagen)
- [ ] GitHub Actions workflow kopiëren naar `.github/workflows/security-agent.yml`
- [ ] GitHub Secrets instellen (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `ANTHROPIC_API_KEY`)
- [ ] Python agent bestanden kopiëren
- [ ] Handmatig testen met curl
- [ ] GitHub Actions handmatig triggeren
- [ ] Eerste scan reviewen en irrelevante checks excluden
- [ ] Gevonden issues fixen met migratie
- [ ] Sentry EU project aanmaken (Frankfurt data residency)
- [ ] `SENTRY_DSN` instellen als Supabase secret en GitHub secret
- [ ] Documentatie bijwerken (CLAUDE.md, README.md)
