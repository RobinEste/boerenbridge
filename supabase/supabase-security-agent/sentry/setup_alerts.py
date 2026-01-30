#!/usr/bin/env python3
"""
Sentry Alert Setup Script

This script creates alert rules in Sentry for the Security Agent.
Run this once after setting up your Sentry project.

Usage:
    python setup_alerts.py

Environment variables required:
    SENTRY_AUTH_TOKEN     - Sentry API auth token (from sentry.io/settings/account/api/auth-tokens/)
    SENTRY_ORG            - Your Sentry organization slug
    SENTRY_PROJECT        - Your Sentry project slug
    SLACK_WORKSPACE_ID    - Sentry Slack integration workspace ID (optional)
    SECURITY_TEAM_EMAIL   - Email for security alerts
    DEVOPS_EMAIL          - Email for ops alerts
    CTO_EMAIL             - Email for critical alerts (optional)
"""

import os
import sys
import json
import requests
from typing import Optional

# Sentry API base URL
SENTRY_API = "https://sentry.io/api/0"


def get_env(name: str, required: bool = True, default: str = None) -> Optional[str]:
    """Get environment variable."""
    value = os.environ.get(name, default)
    if required and not value:
        print(f"❌ Missing required environment variable: {name}")
        sys.exit(1)
    return value


class SentryAlertSetup:
    def __init__(self):
        self.token = get_env("SENTRY_AUTH_TOKEN")
        self.org = get_env("SENTRY_ORG")
        self.project = get_env("SENTRY_PROJECT")
        
        # Optional configs
        self.slack_workspace = get_env("SLACK_WORKSPACE_ID", required=False)
        self.security_email = get_env("SECURITY_TEAM_EMAIL", required=False, default="")
        self.devops_email = get_env("DEVOPS_EMAIL", required=False, default="")
        self.cto_email = get_env("CTO_EMAIL", required=False, default="")
        
        self.headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }
    
    def _api_request(self, method: str, endpoint: str, data: dict = None) -> dict:
        """Make API request to Sentry."""
        url = f"{SENTRY_API}{endpoint}"
        
        response = requests.request(
            method=method,
            url=url,
            headers=self.headers,
            json=data
        )
        
        if response.status_code >= 400:
            print(f"❌ API Error: {response.status_code}")
            print(response.text)
            return None
        
        return response.json() if response.text else {}
    
    def list_existing_rules(self) -> list:
        """List existing alert rules."""
        endpoint = f"/projects/{self.org}/{self.project}/rules/"
        return self._api_request("GET", endpoint) or []
    
    def delete_rule(self, rule_id: int) -> bool:
        """Delete an alert rule."""
        endpoint = f"/projects/{self.org}/{self.project}/rules/{rule_id}/"
        result = self._api_request("DELETE", endpoint)
        return result is not None
    
    def create_issue_alert(self, name: str, conditions: list, actions: list, 
                           frequency: int = 30, action_match: str = "all",
                           filter_match: str = "all", environment: str = None) -> dict:
        """Create an issue alert rule."""
        endpoint = f"/projects/{self.org}/{self.project}/rules/"
        
        payload = {
            "name": name,
            "actionMatch": action_match,
            "filterMatch": filter_match,
            "frequency": frequency,
            "conditions": conditions,
            "actions": actions
        }
        
        if environment:
            payload["environment"] = environment
        
        return self._api_request("POST", endpoint, payload)
    
    def create_critical_vulnerability_alert(self) -> dict:
        """Create alert for critical vulnerabilities."""
        print("📝 Creating: Critical Vulnerability Alert...")
        
        conditions = [
            {
                "id": "sentry.rules.conditions.first_seen_event.FirstSeenEventCondition"
            }
        ]
        
        # Add tag filter
        filters = [
            {
                "id": "sentry.rules.filters.tagged_event.TaggedEventFilter",
                "key": "severity",
                "match": "eq",
                "value": "critical"
            }
        ]
        
        actions = []
        
        # Add Slack action if configured
        if self.slack_workspace:
            actions.append({
                "id": "sentry.integrations.slack.notify_action.SlackNotifyServiceAction",
                "workspace": self.slack_workspace,
                "channel": "#security-alerts",
                "tags": "severity,vulnerability_type,affected_count"
            })
        
        # Add email actions
        if self.security_email:
            actions.append({
                "id": "sentry.mail.actions.NotifyEmailAction",
                "targetType": "Member",
                "fallthroughType": "AllMembers"
            })
        
        return self.create_issue_alert(
            name="🚨 Critical Security Vulnerability",
            conditions=conditions + filters,
            actions=actions,
            frequency=5,
            environment="production"
        )
    
    def create_high_severity_alert(self) -> dict:
        """Create alert for high severity vulnerabilities."""
        print("📝 Creating: High Severity Alert...")
        
        conditions = [
            {
                "id": "sentry.rules.conditions.first_seen_event.FirstSeenEventCondition"
            }
        ]
        
        filters = [
            {
                "id": "sentry.rules.filters.tagged_event.TaggedEventFilter",
                "key": "severity",
                "match": "eq",
                "value": "high"
            }
        ]
        
        actions = []
        
        if self.slack_workspace:
            actions.append({
                "id": "sentry.integrations.slack.notify_action.SlackNotifyServiceAction",
                "workspace": self.slack_workspace,
                "channel": "#security-alerts",
                "tags": "severity,vulnerability_type"
            })
        
        actions.append({
            "id": "sentry.mail.actions.NotifyEmailAction",
            "targetType": "Member",
            "fallthroughType": "AllMembers"
        })
        
        return self.create_issue_alert(
            name="⚠️ High Severity Vulnerability",
            conditions=conditions + filters,
            actions=actions,
            frequency=15,
            environment="production"
        )
    
    def create_agent_error_alert(self) -> dict:
        """Create alert for agent errors."""
        print("📝 Creating: Agent Error Alert...")
        
        conditions = [
            {
                "id": "sentry.rules.conditions.event_frequency.EventFrequencyCondition",
                "interval": "1h",
                "value": 5,
                "comparisonType": "count"
            }
        ]
        
        filters = [
            {
                "id": "sentry.rules.filters.tagged_event.TaggedEventFilter",
                "key": "component",
                "match": "eq",
                "value": "security-agent"
            }
        ]
        
        actions = []
        
        if self.slack_workspace:
            actions.append({
                "id": "sentry.integrations.slack.notify_action.SlackNotifyServiceAction",
                "workspace": self.slack_workspace,
                "channel": "#ops-alerts"
            })
        
        actions.append({
            "id": "sentry.mail.actions.NotifyEmailAction",
            "targetType": "Member",
            "fallthroughType": "AllMembers"
        })
        
        return self.create_issue_alert(
            name="🔧 Security Agent Error Spike",
            conditions=conditions + filters,
            actions=actions,
            frequency=60,
            environment="production"
        )
    
    def create_llm_error_alert(self) -> dict:
        """Create alert for Claude API errors."""
        print("📝 Creating: LLM Error Alert...")
        
        conditions = [
            {
                "id": "sentry.rules.conditions.first_seen_event.FirstSeenEventCondition"
            }
        ]
        
        filters = [
            {
                "id": "sentry.rules.filters.tagged_event.TaggedEventFilter",
                "key": "error_type",
                "match": "eq",
                "value": "llm"
            }
        ]
        
        actions = []
        
        if self.slack_workspace:
            actions.append({
                "id": "sentry.integrations.slack.notify_action.SlackNotifyServiceAction",
                "workspace": self.slack_workspace,
                "channel": "#ops-alerts"
            })
        
        actions.append({
            "id": "sentry.mail.actions.NotifyEmailAction",
            "targetType": "Member",
            "fallthroughType": "AllMembers"
        })
        
        return self.create_issue_alert(
            name="🤖 Claude API Errors",
            conditions=conditions + filters,
            actions=actions,
            frequency=30,
            environment="production"
        )
    
    def create_github_error_alert(self) -> dict:
        """Create alert for GitHub API errors."""
        print("📝 Creating: GitHub Error Alert...")
        
        conditions = [
            {
                "id": "sentry.rules.conditions.first_seen_event.FirstSeenEventCondition"
            }
        ]
        
        filters = [
            {
                "id": "sentry.rules.filters.tagged_event.TaggedEventFilter",
                "key": "error_type",
                "match": "eq",
                "value": "github"
            }
        ]
        
        actions = []
        
        if self.slack_workspace:
            actions.append({
                "id": "sentry.integrations.slack.notify_action.SlackNotifyServiceAction",
                "workspace": self.slack_workspace,
                "channel": "#ops-alerts"
            })
        
        actions.append({
            "id": "sentry.mail.actions.NotifyEmailAction",
            "targetType": "Member",
            "fallthroughType": "AllMembers"
        })
        
        return self.create_issue_alert(
            name="🐙 GitHub API Errors",
            conditions=conditions + filters,
            actions=actions,
            frequency=30,
            environment="production"
        )
    
    def setup_all_alerts(self, clean: bool = False):
        """Set up all alert rules."""
        print(f"\n🔧 Setting up Sentry alerts for {self.org}/{self.project}\n")
        
        if clean:
            print("🧹 Cleaning existing rules...")
            existing = self.list_existing_rules()
            for rule in existing:
                if rule.get("name", "").startswith(("🚨", "⚠️", "🔧", "🤖", "🐙", "📊")):
                    print(f"   Deleting: {rule['name']}")
                    self.delete_rule(rule["id"])
        
        results = []
        
        # Create all alerts
        results.append(("Critical Vulnerability", self.create_critical_vulnerability_alert()))
        results.append(("High Severity", self.create_high_severity_alert()))
        results.append(("Agent Errors", self.create_agent_error_alert()))
        results.append(("LLM Errors", self.create_llm_error_alert()))
        results.append(("GitHub Errors", self.create_github_error_alert()))
        
        # Print results
        print("\n" + "=" * 50)
        print("📊 Results:")
        print("=" * 50)
        
        for name, result in results:
            if result:
                print(f"   ✅ {name}: Created (ID: {result.get('id', 'unknown')})")
            else:
                print(f"   ❌ {name}: Failed")
        
        print("\n✨ Done! Check your Sentry dashboard: ")
        print(f"   https://sentry.io/organizations/{self.org}/alerts/rules/")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Set up Sentry alert rules")
    parser.add_argument("--clean", action="store_true", 
                        help="Remove existing security agent alerts first")
    parser.add_argument("--list", action="store_true",
                        help="List existing alert rules")
    
    args = parser.parse_args()
    
    setup = SentryAlertSetup()
    
    if args.list:
        print("\n📋 Existing alert rules:\n")
        rules = setup.list_existing_rules()
        for rule in rules:
            print(f"   [{rule['id']}] {rule['name']}")
        return
    
    setup.setup_all_alerts(clean=args.clean)


if __name__ == "__main__":
    main()
