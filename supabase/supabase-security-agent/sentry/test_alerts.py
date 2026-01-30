#!/usr/bin/env python3
"""
Sentry Alert Test Script

This script sends test events to Sentry to verify your alerts are working.
Run this after setting up alert rules.

Usage:
    python test_alerts.py --critical    # Test critical vulnerability alert
    python test_alerts.py --high        # Test high severity alert
    python test_alerts.py --error       # Test agent error alert
    python test_alerts.py --all         # Test all alerts

Environment variables required:
    SENTRY_DSN - Your Sentry project DSN
"""

import os
import sys
import time
import argparse

try:
    import sentry_sdk
except ImportError:
    print("❌ sentry-sdk not installed. Run: pip install sentry-sdk")
    sys.exit(1)


def init_sentry():
    """Initialize Sentry SDK."""
    dsn = os.environ.get("SENTRY_DSN")
    if not dsn:
        print("❌ SENTRY_DSN environment variable not set")
        sys.exit(1)
    
    sentry_sdk.init(
        dsn=dsn,
        environment="test",
        release="security-agent@test",
        traces_sample_rate=1.0,
    )
    
    # Set default tags
    sentry_sdk.set_tag("component", "security-agent")
    sentry_sdk.set_tag("test", "true")
    
    print(f"✅ Sentry initialized with DSN: {dsn[:50]}...")


def test_critical_vulnerability():
    """Send a test critical vulnerability event."""
    print("\n🚨 Sending CRITICAL vulnerability test event...")
    
    with sentry_sdk.push_scope() as scope:
        scope.set_level("fatal")
        scope.set_tag("severity", "critical")
        scope.set_tag("event_type", "vulnerability")
        scope.set_tag("vulnerability_type", "test_auth_users_exposed")
        scope.set_tag("affected_count", "1")
        
        scope.set_context("vulnerability", {
            "check_id": "test_auth_users_exposed",
            "check_name": "TEST: Auth Users Exposed",
            "severity": "critical",
            "affected_count": 1,
            "affected_objects": [
                {"schema": "auth", "name": "users", "type": "table"}
            ]
        })
        
        scope.set_fingerprint(["test-critical-vulnerability"])
        
        event_id = sentry_sdk.capture_message(
            "Security Vulnerability: TEST - Auth Users Exposed (IGNORE)",
            level="fatal"
        )
    
    print(f"   ✅ Event sent: {event_id}")
    print("   📧 Check your email and Slack for the alert!")
    return event_id


def test_high_vulnerability():
    """Send a test high severity vulnerability event."""
    print("\n⚠️ Sending HIGH severity vulnerability test event...")
    
    with sentry_sdk.push_scope() as scope:
        scope.set_level("error")
        scope.set_tag("severity", "high")
        scope.set_tag("event_type", "vulnerability")
        scope.set_tag("vulnerability_type", "test_rls_disabled")
        scope.set_tag("affected_count", "3")
        
        scope.set_context("vulnerability", {
            "check_id": "test_rls_disabled",
            "check_name": "TEST: RLS Disabled on Tables",
            "severity": "high",
            "affected_count": 3,
            "affected_objects": [
                {"schema": "public", "name": "users", "type": "table"},
                {"schema": "public", "name": "orders", "type": "table"},
                {"schema": "public", "name": "payments", "type": "table"}
            ]
        })
        
        scope.set_fingerprint(["test-high-vulnerability"])
        
        event_id = sentry_sdk.capture_message(
            "Security Vulnerability: TEST - RLS Disabled (IGNORE)",
            level="error"
        )
    
    print(f"   ✅ Event sent: {event_id}")
    print("   📧 Check your email and Slack for the alert!")
    return event_id


def test_agent_error():
    """Send a test agent error event."""
    print("\n🔧 Sending agent ERROR test event...")
    
    with sentry_sdk.push_scope() as scope:
        scope.set_level("error")
        scope.set_tag("error_type", "agent")
        scope.set_tag("operation", "test_process_issue")
        
        scope.set_context("agent", {
            "model": "claude-sonnet-4-20250514",
            "operation": "test_analyze_vulnerability",
            "issue_number": 999
        })
        
        scope.set_fingerprint(["test-agent-error"])
        
        try:
            raise ValueError("TEST: Agent processing failed (IGNORE)")
        except Exception as e:
            event_id = sentry_sdk.capture_exception(e)
    
    print(f"   ✅ Event sent: {event_id}")
    return event_id


def test_llm_error():
    """Send a test LLM/Claude API error event."""
    print("\n🤖 Sending LLM ERROR test event...")
    
    with sentry_sdk.push_scope() as scope:
        scope.set_level("error")
        scope.set_tag("error_type", "llm")
        scope.set_tag("model", "claude-sonnet-4-20250514")
        scope.set_tag("operation", "test_analyze")
        
        scope.set_context("llm", {
            "model": "claude-sonnet-4-20250514",
            "operation": "test_analyze_vulnerability",
            "prompt_length": 1234
        })
        
        scope.set_fingerprint(["test-llm-error"])
        
        try:
            raise ConnectionError("TEST: Claude API timeout (IGNORE)")
        except Exception as e:
            event_id = sentry_sdk.capture_exception(e)
    
    print(f"   ✅ Event sent: {event_id}")
    return event_id


def test_github_error():
    """Send a test GitHub API error event."""
    print("\n🐙 Sending GitHub ERROR test event...")
    
    with sentry_sdk.push_scope() as scope:
        scope.set_level("error")
        scope.set_tag("error_type", "github")
        scope.set_tag("github_operation", "test_create_pr")
        scope.set_tag("issue_number", "999")
        
        scope.set_context("github", {
            "operation": "test_create_pr",
            "repo": "test-org/test-repo",
            "issue_number": 999
        })
        
        scope.set_fingerprint(["test-github-error"])
        
        try:
            raise PermissionError("TEST: GitHub API rate limit (IGNORE)")
        except Exception as e:
            event_id = sentry_sdk.capture_exception(e)
    
    print(f"   ✅ Event sent: {event_id}")
    return event_id


def flush_and_wait():
    """Flush Sentry events and wait for delivery."""
    print("\n⏳ Flushing events to Sentry...")
    sentry_sdk.flush(timeout=10)
    print("   ✅ Events flushed")
    print("\n💡 Note: Alerts may take 1-2 minutes to arrive depending on your Sentry plan.")


def main():
    parser = argparse.ArgumentParser(description="Test Sentry alert rules")
    parser.add_argument("--critical", action="store_true", 
                        help="Test critical vulnerability alert")
    parser.add_argument("--high", action="store_true",
                        help="Test high severity alert")
    parser.add_argument("--error", action="store_true",
                        help="Test agent error alert")
    parser.add_argument("--llm", action="store_true",
                        help="Test LLM error alert")
    parser.add_argument("--github", action="store_true",
                        help="Test GitHub error alert")
    parser.add_argument("--all", action="store_true",
                        help="Test all alerts")
    
    args = parser.parse_args()
    
    # If no flags, show help
    if not any([args.critical, args.high, args.error, args.llm, args.github, args.all]):
        parser.print_help()
        print("\n💡 Example: python test_alerts.py --critical")
        return
    
    print("=" * 60)
    print("🧪 SENTRY ALERT TEST SCRIPT")
    print("=" * 60)
    print("\n⚠️  This will send TEST events to your Sentry project.")
    print("   Events are tagged with 'test: true' for easy filtering.\n")
    
    init_sentry()
    
    events = []
    
    if args.critical or args.all:
        events.append(test_critical_vulnerability())
        time.sleep(1)
    
    if args.high or args.all:
        events.append(test_high_vulnerability())
        time.sleep(1)
    
    if args.error or args.all:
        events.append(test_agent_error())
        time.sleep(1)
    
    if args.llm or args.all:
        events.append(test_llm_error())
        time.sleep(1)
    
    if args.github or args.all:
        events.append(test_github_error())
    
    flush_and_wait()
    
    print("\n" + "=" * 60)
    print("📊 SUMMARY")
    print("=" * 60)
    print(f"\n   Sent {len(events)} test event(s)")
    print("\n   Next steps:")
    print("   1. Check your Sentry dashboard for the events")
    print("   2. Check your email inbox for alert notifications")
    print("   3. Check your Slack channel for alert messages")
    print("\n   To filter out test events in Sentry:")
    print("   Use query: !tags.test:true")
    print("\n" + "=" * 60)


if __name__ == "__main__":
    main()
