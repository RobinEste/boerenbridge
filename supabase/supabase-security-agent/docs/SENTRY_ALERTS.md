# Sentry Alerts Configuration

Dit document beschrijft de aanbevolen alert rules voor de Supabase Security Agent.

## Quick Setup via Sentry Dashboard

### Stap 1: Slack Integratie

1. Ga naar **Settings → Integrations → Slack**
2. Klik **Add Workspace**
3. Authoriseer Sentry in je Slack workspace
4. Selecteer het kanaal (bijv. `#security-alerts`)

### Stap 2: Email Verificatie

1. Ga naar **Settings → Account → Emails**
2. Voeg team email adressen toe
3. Verifieer via de confirmation link

### Stap 3: Alert Rules Aanmaken

Ga naar **Alerts → Create Alert Rule** en maak de volgende rules:

---

## Aanbevolen Alert Rules

### 🚨 Rule 1: Critical Vulnerability - Immediate Alert

**Trigger:** Zodra een critical security vulnerability wordt gedetecteerd.

```yaml
Name: Critical Security Vulnerability
Environment: production
Conditions:
  - Event's tags match: severity equals "critical"
  - Event's message contains: "Security Vulnerability"
  
Actions:
  - Send Slack notification to #security-alerts
  - Send email to security-team@company.com
  - Send email to cto@company.com
  
Action Interval: 5 minutes (prevent spam)
```

**Dashboard configuratie:**
1. Alerts → Create Alert → Issue Alert
2. Filter: `tags.severity:critical`
3. When: "A new issue is created"
4. Actions: Add Slack + Email

---

### ⚠️ Rule 2: High Severity Vulnerability

**Trigger:** High severity vulnerabilities, gebundeld per uur.

```yaml
Name: High Severity Vulnerabilities
Environment: production
Conditions:
  - Event's tags match: severity equals "high"
  - Event count is greater than 0 in 1 hour

Actions:
  - Send Slack notification to #security-alerts
  - Send email to security-team@company.com

Action Interval: 1 hour (digest)
```

---

### 🔧 Rule 3: Agent Processing Errors

**Trigger:** Wanneer de agent faalt bij het verwerken van issues.

```yaml
Name: Security Agent Errors
Environment: production
Conditions:
  - Event's level equals: error OR fatal
  - Event's tags match: component equals "security-agent"
  - Event count is greater than 3 in 30 minutes

Actions:
  - Send Slack notification to #ops-alerts
  - Send email to devops@company.com

Action Interval: 30 minutes
```

---

### 🐢 Rule 4: Performance Degradation

**Trigger:** Wanneer scans te lang duren.

```yaml
Name: Slow Security Scans
Type: Metric Alert
Metric: transaction.duration
Query: transaction:"/security-scanner"

Conditions:
  - p95 > 60000ms over 1 hour

Actions:
  - Send Slack notification to #ops-alerts
  - Send email to devops@company.com

Action Interval: 1 hour
```

---

### 🤖 Rule 5: LLM/Claude API Failures

**Trigger:** Problemen met de Claude API.

```yaml
Name: Claude API Failures
Environment: production
Conditions:
  - Event's tags match: error_type equals "llm"
  - Event count is greater than 2 in 15 minutes

Actions:
  - Send Slack notification to #ops-alerts
  - Send email to devops@company.com

Action Interval: 15 minutes
```

---

### 📊 Rule 6: Daily Security Summary

**Trigger:** Dagelijkse samenvatting van alle findings.

```yaml
Name: Daily Security Summary
Type: Metric Alert
Schedule: Daily at 09:00

Query: 
  - Count events where tags.event_type = "vulnerability"
  - Group by tags.severity

Actions:
  - Send email digest to security-team@company.com
  - Send Slack summary to #security-daily

Action Interval: 24 hours
```

---

## Slack Message Format

De Slack notificaties zien er zo uit:

```
🚨 Critical Security Vulnerability Detected

Project: supabase-security-agent
Environment: production

Security Vulnerability: Auth Users Exposed

Tags:
• severity: critical
• vulnerability_type: auth_users_exposed
• affected_count: 1

View in Sentry →
```

---

## Email Template

Sentry stuurt emails in dit format:

```
Subject: [Critical] Security Vulnerability: Auth Users Exposed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🚨 CRITICAL SECURITY VULNERABILITY

Project: supabase-security-agent
Environment: production
First seen: 2025-01-30 14:32:00 UTC

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Security Vulnerability: Auth Users Exposed

The auth.users table is accessible via the public API,
potentially exposing user credentials and PII.

Affected Objects:
• auth.users

Tags:
• severity: critical  
• category: authentication
• scan_id: abc-123-def

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

View Issue: https://sentry.io/issues/12345/
Resolve: https://sentry.io/issues/12345/resolve/

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Programmatic Setup (Optional)

Als je alerts wilt automatiseren via de Sentry API:

```python
import requests

SENTRY_API_TOKEN = "your-auth-token"
SENTRY_ORG = "your-org"
SENTRY_PROJECT = "supabase-security-agent"

def create_alert_rule(name, conditions, actions):
    """Create an alert rule via Sentry API."""
    url = f"https://sentry.io/api/0/projects/{SENTRY_ORG}/{SENTRY_PROJECT}/rules/"
    
    headers = {
        "Authorization": f"Bearer {SENTRY_API_TOKEN}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "name": name,
        "conditions": conditions,
        "actions": actions,
        "actionMatch": "all",
        "frequency": 30  # minutes
    }
    
    response = requests.post(url, headers=headers, json=payload)
    return response.json()


# Example: Create critical vulnerability alert
create_alert_rule(
    name="Critical Security Vulnerability",
    conditions=[
        {
            "id": "sentry.rules.conditions.tagged_event.TaggedEventCondition",
            "key": "severity",
            "match": "eq",
            "value": "critical"
        }
    ],
    actions=[
        {
            "id": "sentry.integrations.slack.notify_action.SlackNotifyServiceAction",
            "workspace": "your-workspace-id",
            "channel": "#security-alerts"
        },
        {
            "id": "sentry.mail.actions.NotifyEmailAction",
            "targetType": "Team",
            "targetIdentifier": "security-team"
        }
    ]
)
```

---

## Environment Variables voor Alerts

Voeg deze toe aan je `.env` voor alert customization:

```bash
# Alert recipients
ALERT_EMAIL_CRITICAL=security-team@company.com,cto@company.com
ALERT_EMAIL_HIGH=security-team@company.com
ALERT_EMAIL_OPS=devops@company.com

# Slack channels
ALERT_SLACK_SECURITY=#security-alerts
ALERT_SLACK_OPS=#ops-alerts
ALERT_SLACK_DAILY=#security-daily

# Alert thresholds
ALERT_SCAN_DURATION_THRESHOLD_MS=60000
ALERT_ERROR_COUNT_THRESHOLD=5
```

---

## Escalation Matrix

| Severity | Response Time | Notify |
|----------|---------------|--------|
| Critical | < 15 min | Slack + Email + PagerDuty |
| High | < 1 hour | Slack + Email |
| Medium | < 24 hours | Daily digest |
| Low | Next sprint | Weekly report |

---

## Testing Alerts

Test je alerts met dit script:

```python
import sentry_sdk

sentry_sdk.init(dsn="your-dsn")

# Test critical alert
with sentry_sdk.push_scope() as scope:
    scope.set_tag("severity", "critical")
    scope.set_tag("event_type", "vulnerability")
    scope.set_tag("vulnerability_type", "test_alert")
    scope.set_context("vulnerability", {
        "check_name": "TEST: Alert Configuration",
        "affected_count": 1,
    })
    sentry_sdk.capture_message(
        "Security Vulnerability: TEST - Please ignore",
        level="fatal"
    )

print("Test alert sent! Check Slack and email.")
```

---

## Troubleshooting

### Alerts komen niet aan

1. **Check Slack integration**: Settings → Integrations → Slack → Test
2. **Check email verification**: Settings → Account → Emails
3. **Check alert rule conditions**: Zorg dat tags exact matchen
4. **Check rate limits**: Action interval niet te kort

### Te veel alerts

1. Verhoog de **Action Interval** 
2. Gebruik **event count > X** conditions
3. Group by `fingerprint` om duplicates te voorkomen

### Alerts gaan naar verkeerde mensen

1. Check **Team** configuratie in Sentry
2. Verify email adressen in alert actions
3. Check Slack channel permissions
