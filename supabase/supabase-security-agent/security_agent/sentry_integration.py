"""
Sentry Integration for Security Agent

Provides error tracking, performance monitoring, and custom events
for the Claude-powered security agent.
"""

import os
import functools
from typing import Optional, Callable, Any, Dict
from contextlib import contextmanager

import sentry_sdk
from sentry_sdk import capture_exception, capture_message, set_tag, set_context
from sentry_sdk.integrations.logging import LoggingIntegration


def init_sentry(
    dsn: Optional[str] = None,
    environment: Optional[str] = None,
    release: Optional[str] = None,
) -> bool:
    """
    Initialize Sentry SDK for the security agent.
    
    Args:
        dsn: Sentry DSN (defaults to SENTRY_DSN env var)
        environment: Environment name (defaults to SENTRY_ENVIRONMENT or 'production')
        release: Release version (defaults to SENTRY_RELEASE or 'security-agent@1.0.0')
    
    Returns:
        True if initialization succeeded, False otherwise
    """
    dsn = dsn or os.environ.get('SENTRY_DSN')
    
    if not dsn:
        print("Warning: SENTRY_DSN not set, Sentry monitoring disabled")
        return False
    
    environment = environment or os.environ.get('SENTRY_ENVIRONMENT', 'production')
    release = release or os.environ.get('SENTRY_RELEASE', 'security-agent@1.0.0')
    
    # Configure logging integration
    logging_integration = LoggingIntegration(
        level=None,  # Capture all levels as breadcrumbs
        event_level=None  # Don't send logs as events (we'll do it explicitly)
    )
    
    sentry_sdk.init(
        dsn=dsn,
        environment=environment,
        release=release,
        
        # Performance monitoring
        traces_sample_rate=1.0,  # Capture all transactions for security scans
        profiles_sample_rate=0.5,  # Profile 50% of transactions
        
        # Integrations
        integrations=[logging_integration],
        
        # Data scrubbing
        before_send=_sanitize_event,
        
        # Default tags
        default_integrations=True,
    )
    
    # Set default tags
    set_tag('component', 'security-agent')
    set_tag('runtime', 'python')
    
    print(f"Sentry initialized: environment={environment}, release={release}")
    return True


def _sanitize_event(event: Dict, hint: Dict) -> Dict:
    """Remove sensitive data from Sentry events."""
    
    # Sanitize exception messages
    if 'exception' in event:
        for exception in event.get('exception', {}).get('values', []):
            if 'value' in exception:
                exception['value'] = _sanitize_string(exception['value'])
    
    # Sanitize breadcrumb messages
    if 'breadcrumbs' in event:
        for breadcrumb in event.get('breadcrumbs', {}).get('values', []):
            if 'message' in breadcrumb:
                breadcrumb['message'] = _sanitize_string(breadcrumb['message'])
    
    # Sanitize message events
    if 'message' in event:
        event['message'] = _sanitize_string(event['message'])
    
    return event


def _sanitize_string(text: str) -> str:
    """Remove potential secrets from a string."""
    import re
    
    # Remove JWT tokens
    text = re.sub(
        r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*',
        '[REDACTED_JWT]',
        text
    )
    
    # Remove API keys (common patterns)
    text = re.sub(r'sk[-_][A-Za-z0-9]{20,}', '[REDACTED_KEY]', text)
    text = re.sub(r'ghp_[A-Za-z0-9]{36}', '[REDACTED_GITHUB_TOKEN]', text)
    text = re.sub(r'sk-ant-[A-Za-z0-9-]+', '[REDACTED_ANTHROPIC_KEY]', text)
    
    # Remove passwords in connection strings
    text = re.sub(r'password=[^&\s]+', 'password=[REDACTED]', text, flags=re.IGNORECASE)
    
    return text


@contextmanager
def sentry_transaction(name: str, op: str = 'task'):
    """
    Context manager to create a Sentry transaction.
    
    Usage:
        with sentry_transaction('process-vulnerability', 'agent') as transaction:
            # Your code here
            transaction.set_tag('severity', 'high')
    """
    with sentry_sdk.start_transaction(name=name, op=op) as transaction:
        try:
            yield transaction
        except Exception as e:
            transaction.set_status('internal_error')
            capture_exception(e)
            raise
        else:
            transaction.set_status('ok')


@contextmanager
def sentry_span(description: str, op: str = 'task'):
    """
    Context manager to create a Sentry span within the current transaction.
    
    Usage:
        with sentry_span('analyze-vulnerability', 'llm') as span:
            # Your code here
            span.set_data('model', 'claude-sonnet-4-20250514')
    """
    with sentry_sdk.start_span(description=description, op=op) as span:
        try:
            yield span
        except Exception as e:
            span.set_status('internal_error')
            capture_exception(e)
            raise
        else:
            span.set_status('ok')


def track_performance(op: str = 'function'):
    """
    Decorator to automatically track function performance in Sentry.
    
    Usage:
        @track_performance('agent.analyze')
        def analyze_vulnerability(vuln):
            ...
    """
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            with sentry_span(func.__name__, op):
                return func(*args, **kwargs)
        return wrapper
    return decorator


def set_vulnerability_context(
    check_id: str,
    check_name: str,
    severity: str,
    affected_count: int,
    affected_objects: Optional[list] = None,
) -> None:
    """Set Sentry context for a vulnerability being processed."""
    set_context('vulnerability', {
        'check_id': check_id,
        'check_name': check_name,
        'severity': severity,
        'affected_count': affected_count,
        'affected_objects': (affected_objects or [])[:10],  # Limit to 10
    })
    
    set_tag('vulnerability_type', check_id)
    set_tag('severity', severity)


def set_issue_context(
    issue_number: int,
    issue_title: str,
    repo: str,
) -> None:
    """Set Sentry context for a GitHub issue being processed."""
    set_context('github_issue', {
        'number': issue_number,
        'title': issue_title,
        'repo': repo,
    })
    
    set_tag('issue_number', str(issue_number))


def set_agent_context(
    model: str,
    operation: str,
    config: Optional[Dict] = None,
) -> None:
    """Set Sentry context for agent operations."""
    context = {
        'model': model,
        'operation': operation,
    }
    if config:
        context['config'] = config
    
    set_context('agent', context)
    set_tag('model', model)
    set_tag('operation', operation)


def record_vulnerability_event(
    check_id: str,
    check_name: str,
    severity: str,
    affected_count: int,
    scan_id: Optional[str] = None,
) -> None:
    """
    Record a vulnerability finding as a Sentry event.
    Creates a trackable issue for each unique vulnerability type.
    """
    level = _severity_to_sentry_level(severity)
    
    with sentry_sdk.push_scope() as scope:
        scope.set_level(level)
        scope.set_tag('event_type', 'vulnerability')
        scope.set_tag('vulnerability_type', check_id)
        scope.set_tag('severity', severity)
        
        if scan_id:
            scope.set_tag('scan_id', scan_id)
        
        scope.set_context('vulnerability', {
            'check_id': check_id,
            'check_name': check_name,
            'severity': severity,
            'affected_count': affected_count,
        })
        
        # Set fingerprint for grouping similar vulnerabilities
        scope.set_fingerprint(['security-vulnerability', check_id])
        
        capture_message(
            f"Security Vulnerability: {check_name}",
            level=level,
        )


def record_fix_generated(
    check_id: str,
    issue_number: int,
    pr_url: Optional[str] = None,
    risk_level: str = 'unknown',
) -> None:
    """Record that a fix was generated for a vulnerability."""
    with sentry_sdk.push_scope() as scope:
        scope.set_level('info')
        scope.set_tag('event_type', 'fix_generated')
        scope.set_tag('vulnerability_type', check_id)
        scope.set_tag('risk_level', risk_level)
        
        scope.set_context('fix', {
            'check_id': check_id,
            'issue_number': issue_number,
            'pr_url': pr_url,
            'risk_level': risk_level,
        })
        
        capture_message(
            f"Fix Generated: {check_id} (Issue #{issue_number})",
            level='info',
        )


def record_pr_created(
    issue_number: int,
    pr_number: int,
    pr_url: str,
    check_id: str,
) -> None:
    """Record that a PR was created."""
    sentry_sdk.add_breadcrumb(
        category='github',
        message=f'Created PR #{pr_number} for issue #{issue_number}',
        level='info',
        data={
            'pr_url': pr_url,
            'check_id': check_id,
        },
    )


def _severity_to_sentry_level(severity: str) -> str:
    """Map vulnerability severity to Sentry level."""
    mapping = {
        'critical': 'fatal',
        'high': 'error',
        'medium': 'warning',
        'low': 'info',
        'info': 'info',
    }
    return mapping.get(severity.lower(), 'info')


def capture_llm_error(
    error: Exception,
    model: str,
    operation: str,
    prompt_length: Optional[int] = None,
) -> str:
    """Capture an LLM-related error with context."""
    with sentry_sdk.push_scope() as scope:
        scope.set_tag('error_type', 'llm')
        scope.set_tag('model', model)
        scope.set_tag('operation', operation)
        
        scope.set_context('llm', {
            'model': model,
            'operation': operation,
            'prompt_length': prompt_length,
        })
        
        return capture_exception(error)


def capture_github_error(
    error: Exception,
    operation: str,
    repo: Optional[str] = None,
    issue_number: Optional[int] = None,
) -> str:
    """Capture a GitHub-related error with context."""
    with sentry_sdk.push_scope() as scope:
        scope.set_tag('error_type', 'github')
        scope.set_tag('github_operation', operation)
        
        context = {'operation': operation}
        if repo:
            context['repo'] = repo
        if issue_number:
            context['issue_number'] = issue_number
        
        scope.set_context('github', context)
        
        return capture_exception(error)


def add_breadcrumb(
    message: str,
    category: str = 'agent',
    level: str = 'info',
    data: Optional[Dict] = None,
) -> None:
    """Add a breadcrumb for tracking agent progress."""
    sentry_sdk.add_breadcrumb(
        category=category,
        message=message,
        level=level,
        data=data or {},
    )


class SentryMetrics:
    """Helper class for recording custom metrics."""
    
    @staticmethod
    def record_scan_duration(duration_ms: int, scan_id: str) -> None:
        """Record scan duration metric."""
        sentry_sdk.set_measurement('scan.duration', duration_ms, 'millisecond')
        add_breadcrumb(
            f'Scan completed in {duration_ms}ms',
            category='metrics',
            data={'scan_id': scan_id, 'duration_ms': duration_ms},
        )
    
    @staticmethod
    def record_llm_call(
        model: str,
        input_tokens: int,
        output_tokens: int,
        duration_ms: int,
    ) -> None:
        """Record LLM call metrics."""
        sentry_sdk.set_measurement('llm.input_tokens', input_tokens, 'none')
        sentry_sdk.set_measurement('llm.output_tokens', output_tokens, 'none')
        sentry_sdk.set_measurement('llm.duration', duration_ms, 'millisecond')
        
        add_breadcrumb(
            f'LLM call: {input_tokens} in, {output_tokens} out',
            category='llm',
            data={
                'model': model,
                'input_tokens': input_tokens,
                'output_tokens': output_tokens,
                'duration_ms': duration_ms,
            },
        )
    
    @staticmethod
    def record_vulnerabilities_found(
        total: int,
        critical: int,
        high: int,
        medium: int,
        low: int,
    ) -> None:
        """Record vulnerability count metrics."""
        sentry_sdk.set_measurement('vulnerabilities.total', total, 'none')
        sentry_sdk.set_measurement('vulnerabilities.critical', critical, 'none')
        sentry_sdk.set_measurement('vulnerabilities.high', high, 'none')
        sentry_sdk.set_measurement('vulnerabilities.medium', medium, 'none')
        sentry_sdk.set_measurement('vulnerabilities.low', low, 'none')


# Convenience function for quick initialization
def setup_sentry() -> bool:
    """Quick setup using environment variables."""
    return init_sentry()
