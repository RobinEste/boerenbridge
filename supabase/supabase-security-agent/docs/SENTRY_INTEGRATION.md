# Sentry Integration Guide

Deze guide beschrijft hoe Sentry is geïntegreerd in de Supabase Security Agent en wat je kunt verwachten in je Sentry dashboard.

## Overzicht

De Sentry integratie biedt:

1. **Error Tracking** - Automatische capture van exceptions en errors
2. **Performance Monitoring** - Trace van alle operaties met timing data
3. **Custom Events** - Security vulnerabilities als Sentry issues
4. **Breadcrumbs** - Gedetailleerde audit trail van agent acties

## Setup

### 1. Sentry Project Aanmaken

1. Ga naar [sentry.io](https://sentry.io) en log in
2. Maak een nieuw project aan:
   - Platform: **Python** (voor de agent)
   - Maak nog een project voor: **JavaScript/Deno** (voor de Edge Function)
3. Kopieer de DSN van beide projecten

### 2. Environment Variables

```bash
# Voor de Python Agent
SENTRY_DSN=https://xxx@oyyy.ingest.sentry.io/zzz
SENTRY_ENVIRONMENT=production
SENTRY_RELEASE=security-agent@1.0.0

# Voor de Edge Function (in Supabase Dashboard > Edge Functions > Secrets)
SENTRY_DSN=https://xxx@oyyy.ingest.sentry.io/zzz
SENTRY_ENVIRONMENT=production
SENTRY_RELEASE=security-scanner@1.0.0
```

### 3. GitHub Secrets

Voeg toe aan je repository secrets:
- `SENTRY_DSN` - Je Sentry project DSN

## Wat Je Ziet in Sentry

### Issues View

Je ziet drie soorten issues:

#### 1. Security Vulnerabilities (Custom Events)

```
🔒 Security Vulnerability: RLS Disabled on Public Tables
├── severity: high
├── vulnerability_type: rls_disabled_in_public
├── affected_count: 3
└── scan_id: abc-123
```

Deze worden gegroepeerd per vulnerability type, dus je ziet trends over tijd.

#### 2. Agent Errors

```
❌ ValueError: Claude did not return valid JSON
├── error_type: llm
├── model: claude-sonnet-4-20250514
└── operation: analyze_vulnerability
```

#### 3. Integration Errors

```
❌ GithubException: 422 Validation Failed
├── error_type: github
├── operation: create_pr
└── issue_number: 42
```

### Performance View

Je ziet transactions voor:

| Transaction | Beschrijving |
|-------------|--------------|
| `POST /security-scanner` | Full security scan |
| `process-issue-{n}` | Agent processing een issue |
| `process-all-issues` | Batch processing |

Elke transaction bevat spans voor:
- Individual security checks
- LLM API calls
- GitHub API calls
- Database operations

### Breadcrumbs

Elke error toont een trail van acties:

```
12:00:01 [agent] Security agent initialized
12:00:02 [github] Fetching open security issues
12:00:03 [github] Found 3 unprocessed issues
12:00:04 [parser] Parsing issue #42
12:00:05 [llm] Calling Claude for analysis
12:00:08 [agent] Fix generated for RLS Disabled
12:00:09 [github] Creating PR for issue #42
12:00:10 [github] Created branch: security-fix/rls_disabled-42
12:00:11 ❌ ERROR: GitHub API rate limit exceeded
```

## Custom Metrics

De integratie tracked automatisch:

| Metric | Beschrijving |
|--------|--------------|
| `scan.duration` | Hoe lang een scan duurt (ms) |
| `scan.total_checks` | Aantal uitgevoerde checks |
| `scan.critical_findings` | Aantal critical vulnerabilities |
| `llm.input_tokens` | Claude input tokens |
| `llm.output_tokens` | Claude output tokens |
| `llm.duration` | Claude API response time |

## Alerts Configureren

### Recommended Alert Rules

1. **Critical Vulnerability Detected**
   ```
   When: event.tags.severity = "critical"
   Action: Slack/Email immediately
   ```

2. **Agent Error Rate**
   ```
   When: error count > 5 in 1 hour
   Action: Slack notification
   ```

3. **Scan Performance Degradation**
   ```
   When: p95(scan.duration) > 60000ms
   Action: Email notification
   ```

4. **LLM Failures**
   ```
   When: event.tags.error_type = "llm"
   Action: Slack notification
   ```

## Code Voorbeelden

### Error Tracking in Custom Code

```python
from security_agent.sentry_integration import (
    capture_llm_error,
    capture_github_error,
    add_breadcrumb,
)

# Track een LLM error
try:
    response = client.messages.create(...)
except Exception as e:
    capture_llm_error(e, model="claude-sonnet-4-20250514", operation="analyze")
    raise

# Track een GitHub error
try:
    repo.create_pull(...)
except GithubException as e:
    capture_github_error(e, operation="create_pr", issue_number=42)
    raise

# Voeg context toe
add_breadcrumb("Custom operation completed", category="custom", data={"key": "value"})
```

### Performance Tracking

```python
from security_agent.sentry_integration import sentry_span, track_performance

# Als context manager
with sentry_span("my-operation", "custom"):
    do_something()

# Als decorator
@track_performance("custom.operation")
def my_function():
    pass
```

### Custom Events

```python
from security_agent.sentry_integration import record_vulnerability_event

record_vulnerability_event(
    check_id="custom_check",
    check_name="My Custom Check",
    severity="high",
    affected_count=5,
    scan_id="abc-123",
)
```

## Data Privacy

De integratie sanitized automatisch:
- JWT tokens
- API keys (Anthropic, GitHub, Supabase)
- Passwords in connection strings

Sensitive data wordt vervangen door `[REDACTED_*]` placeholders.

## Troubleshooting

### Events komen niet aan in Sentry

1. Check of `SENTRY_DSN` correct is ingesteld
2. Verify met: `sentry_sdk.capture_message("Test")`
3. Check Sentry project quota en rate limits

### Performance data ontbreekt

1. Ensure `traces_sample_rate` > 0
2. Check of transactions correct worden afgesloten
3. Verify met Sentry Debug mode: `debug=True` in `sentry_sdk.init()`

### Te veel events

1. Verlaag `traces_sample_rate` naar 0.1-0.5
2. Configureer `before_send` om bepaalde events te filteren
3. Gebruik Sentry's ingest filtering rules

## Volgende Stappen

1. **Slack Integration**: Koppel Sentry aan Slack voor real-time alerts
2. **Release Tracking**: Gebruik `SENTRY_RELEASE` met git commit SHA
3. **Source Maps**: Upload source maps voor betere stack traces
4. **Dashboards**: Bouw custom dashboards voor security metrics
