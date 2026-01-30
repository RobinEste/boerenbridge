# Supabase Security Vulnerability Agent

Een geautomatiseerde security scanning pipeline die vulnerabilities in je Supabase project detecteert, 
GitHub Issues aanmaakt, en een Claude SDK agent inzet om oplossingen te genereren.

## Architectuur

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        Security Vulnerability Pipeline                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────────┐                                                           │
│  │    Supabase      │                                                           │
│  │    Database      │                                                           │
│  └────────┬─────────┘                                                           │
│           │                                                                      │
│           ▼                                                                      │
│  ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐        │
│  │  Edge Function   │────▶│  GitHub Issue    │────▶│  GitHub Action   │        │
│  │  Security        │     │  Created with    │     │  Triggers on     │        │
│  │  Scanner         │     │  vulnerability   │     │  'security'      │        │
│  │  (Cron: daily)   │     │  details + label │     │  label           │        │
│  └──────────────────┘     └──────────────────┘     └────────┬─────────┘        │
│                                                              │                  │
│                                                              ▼                  │
│                                                    ┌──────────────────┐        │
│                                                    │  Claude SDK      │        │
│                                                    │  Agent           │        │
│                                                    │  - Analyzes      │        │
│                                                    │  - Generates fix │        │
│                                                    │  - Creates PR    │        │
│                                                    └──────────────────┘        │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Componenten

### 1. Security Scanner (Supabase Edge Function)
- Draait dagelijks via pg_cron of externe scheduler
- Voert 15+ security checks uit op je database
- Detecteert: RLS issues, exposed tables, insecure extensions, etc.
- Stuurt vulnerabilities naar GitHub Issues API

### 2. GitHub Integration
- Issues worden aangemaakt met gestructureerde metadata
- Labels: `security`, `automated`, `severity:high|medium|low`
- Body bevat: vulnerability details, affected objects, remediation hints

### 3. Claude SDK Agent (GitHub Action)
- Triggered wanneer issue met `security` label wordt aangemaakt
- Analyseert vulnerability en genereert SQL migration
- Maakt automatisch een PR aan met de fix
- Voegt test cases toe voor validatie

## Quick Start

### Prerequisites
- Supabase project met Edge Functions enabled
- GitHub repository met Actions enabled
- Anthropic API key

### Installation

1. **Clone en configureer**
```bash
git clone <this-repo>
cd supabase-security-agent

# Kopieer environment template
cp .env.example .env
```

2. **Set environment variables**
```bash
# .env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
GITHUB_TOKEN=ghp_your-token
GITHUB_OWNER=your-org
GITHUB_REPO=your-repo
ANTHROPIC_API_KEY=sk-ant-your-key
```

3. **Deploy Edge Function**
```bash
supabase functions deploy security-scanner
```

4. **Setup GitHub Action**
```bash
# Kopieer workflow naar je repo
cp .github/workflows/security-agent.yml <your-repo>/.github/workflows/
```

5. **Schedule de scanner**
```sql
-- Via pg_cron (of gebruik externe scheduler)
SELECT cron.schedule(
  'security-scan',
  '0 6 * * *',  -- Dagelijks om 6:00 UTC
  $$SELECT net.http_post(
    url := 'https://your-project.supabase.co/functions/v1/security-scanner',
    headers := '{"Authorization": "Bearer your-anon-key"}'::jsonb
  )$$
);
```

## Security Checks

De scanner voert de volgende checks uit:

| Check | Severity | Beschrijving |
|-------|----------|--------------|
| `rls_disabled` | HIGH | Tabellen zonder Row Level Security |
| `rls_no_policy` | HIGH | RLS enabled maar geen policies |
| `auth_users_exposed` | CRITICAL | auth.users accessible via public API |
| `service_role_leaked` | CRITICAL | Service role key in client code |
| `extension_in_public` | MEDIUM | Extensions in public schema |
| `unindexed_fk` | LOW | Foreign keys zonder index |
| `security_definer_view` | MEDIUM | Views met SECURITY DEFINER |
| `permissive_policy` | MEDIUM | Overly permissive RLS policies |
| `sensitive_columns` | HIGH | PII/sensitive data exposed |
| `weak_password_policy` | MEDIUM | Zwakke auth password requirements |
| `mfa_not_enforced` | MEDIUM | MFA niet verplicht voor admins |
| `api_key_in_rls` | HIGH | Hardcoded keys in RLS policies |
| `public_bucket_write` | HIGH | Storage buckets met public write |
| `function_search_path` | MEDIUM | Mutable search_path in functions |
| `outdated_extensions` | LOW | Verouderde extension versies |

## Configuratie

### Scanner Config (`config/scanner.json`)
```json
{
  "enabled_checks": ["all"],
  "severity_threshold": "low",
  "excluded_tables": ["_prisma_migrations"],
  "excluded_schemas": ["pg_catalog", "information_schema"],
  "notifications": {
    "github_issues": true,
    "slack_webhook": null
  }
}
```

### Agent Config (`config/agent.json`)
```json
{
  "model": "claude-sonnet-4-20250514",
  "auto_create_pr": true,
  "require_approval": true,
  "max_tokens": 4096,
  "include_tests": true
}
```

## Development

```bash
# Run scanner locally
supabase functions serve security-scanner

# Test agent locally
python -m security_agent.main --issue-number 123

# Run all tests
pytest tests/
```

## License

MIT
