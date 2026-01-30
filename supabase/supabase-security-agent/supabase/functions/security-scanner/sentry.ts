/**
 * Sentry Integration for Security Scanner
 * 
 * Provides error tracking, performance monitoring, and custom events
 * for the Supabase Security Scanner Edge Function.
 */

import * as Sentry from 'https://deno.land/x/sentry@8.0.0/index.mjs';

// Types for Sentry context
interface ScanContext {
  scan_id: string;
  project_ref: string;
  checks_count: number;
  config: Record<string, unknown>;
}

interface VulnerabilityContext {
  check_id: string;
  check_name: string;
  severity: string;
  affected_count: number;
}

/**
 * Initialize Sentry for the Edge Function
 * Call this at the start of your function
 */
export function initSentry(): void {
  const dsn = Deno.env.get('SENTRY_DSN');
  
  if (!dsn) {
    console.warn('SENTRY_DSN not set, Sentry monitoring disabled');
    return;
  }

  Sentry.init({
    dsn,
    environment: Deno.env.get('SENTRY_ENVIRONMENT') || 'production',
    release: Deno.env.get('SENTRY_RELEASE') || 'security-scanner@1.0.0',
    
    // Performance monitoring
    tracesSampleRate: 1.0, // Capture 100% of transactions for security scans
    
    // Profile the scan performance
    profilesSampleRate: 0.5,
    
    // Filter sensitive data
    beforeSend(event) {
      // Remove any potential secrets from error messages
      if (event.message) {
        event.message = sanitizeMessage(event.message);
      }
      return event;
    },
    
    // Add default tags
    initialScope: {
      tags: {
        component: 'security-scanner',
        runtime: 'deno-edge-function',
      },
    },
  });

  console.log('Sentry initialized for security scanner');
}

/**
 * Remove potential secrets from messages
 */
function sanitizeMessage(message: string): string {
  // Remove JWT tokens
  message = message.replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*/g, '[REDACTED_JWT]');
  // Remove API keys
  message = message.replace(/sk[-_][A-Za-z0-9]{20,}/g, '[REDACTED_KEY]');
  // Remove passwords in connection strings
  message = message.replace(/password=[^&\s]+/gi, 'password=[REDACTED]');
  return message;
}

/**
 * Start a new scan transaction for performance monitoring
 */
export function startScanTransaction(scanId: string, projectRef: string): Sentry.Transaction | null {
  try {
    const transaction = Sentry.startTransaction({
      name: 'security-scan',
      op: 'scan',
      data: {
        scan_id: scanId,
        project_ref: projectRef,
      },
    });

    // Set as current transaction
    Sentry.getCurrentHub().configureScope((scope) => {
      scope.setSpan(transaction);
    });

    return transaction;
  } catch (error) {
    console.error('Failed to start Sentry transaction:', error);
    return null;
  }
}

/**
 * Create a span for individual security checks
 */
export function startCheckSpan(
  transaction: Sentry.Transaction | null, 
  checkId: string, 
  checkName: string
): Sentry.Span | null {
  if (!transaction) return null;

  try {
    return transaction.startChild({
      op: 'security-check',
      description: checkName,
      data: {
        check_id: checkId,
      },
    });
  } catch (error) {
    console.error('Failed to start check span:', error);
    return null;
  }
}

/**
 * Set scan context for all events in this scope
 */
export function setScanContext(context: ScanContext): void {
  Sentry.configureScope((scope) => {
    scope.setContext('scan', context);
    scope.setTag('scan_id', context.scan_id);
    scope.setTag('project_ref', context.project_ref);
  });
}

/**
 * Record a vulnerability finding as a Sentry event
 * This creates a trackable issue for each unique vulnerability type
 */
export function recordVulnerability(
  checkId: string,
  checkName: string,
  severity: string,
  affectedObjects: Array<{ schema: string; name: string; type: string }>,
  scanId: string
): void {
  // Create a custom event for the vulnerability
  Sentry.withScope((scope) => {
    // Set severity level based on vulnerability severity
    const sentryLevel = mapSeverityToSentryLevel(severity);
    scope.setLevel(sentryLevel);

    // Add vulnerability context
    scope.setContext('vulnerability', {
      check_id: checkId,
      check_name: checkName,
      severity,
      affected_count: affectedObjects.length,
      affected_objects: affectedObjects.slice(0, 10), // Limit to first 10
    });

    // Add tags for filtering
    scope.setTag('vulnerability_type', checkId);
    scope.setTag('severity', severity);
    scope.setTag('scan_id', scanId);

    // Set fingerprint for grouping similar vulnerabilities
    scope.setFingerprint(['security-vulnerability', checkId]);

    // Capture as an event (not exception)
    Sentry.captureMessage(
      `Security Vulnerability: ${checkName}`,
      sentryLevel
    );
  });
}

/**
 * Map our severity levels to Sentry severity levels
 */
function mapSeverityToSentryLevel(severity: string): Sentry.SeverityLevel {
  switch (severity) {
    case 'critical':
      return 'fatal';
    case 'high':
      return 'error';
    case 'medium':
      return 'warning';
    case 'low':
      return 'info';
    default:
      return 'info';
  }
}

/**
 * Capture and report an error with scan context
 */
export function captureError(
  error: Error,
  context?: Record<string, unknown>
): string {
  return Sentry.captureException(error, {
    contexts: context ? { additional: context } : undefined,
  });
}

/**
 * Record scan completion metrics
 */
export function recordScanMetrics(
  scanId: string,
  metrics: {
    duration_ms: number;
    total_checks: number;
    passed_checks: number;
    failed_checks: number;
    critical_count: number;
    high_count: number;
    medium_count: number;
    low_count: number;
  }
): void {
  // Set metrics as measurements on the current transaction
  Sentry.setMeasurement('scan.duration', metrics.duration_ms, 'millisecond');
  Sentry.setMeasurement('scan.total_checks', metrics.total_checks, 'none');
  Sentry.setMeasurement('scan.passed_checks', metrics.passed_checks, 'none');
  Sentry.setMeasurement('scan.failed_checks', metrics.failed_checks, 'none');
  Sentry.setMeasurement('scan.critical_findings', metrics.critical_count, 'none');
  Sentry.setMeasurement('scan.high_findings', metrics.high_count, 'none');

  // Also capture as breadcrumb for context
  Sentry.addBreadcrumb({
    category: 'scan',
    message: `Scan completed: ${metrics.failed_checks} vulnerabilities found`,
    level: metrics.critical_count > 0 ? 'error' : 
           metrics.high_count > 0 ? 'warning' : 'info',
    data: metrics,
  });
}

/**
 * Add a breadcrumb for tracking scan progress
 */
export function addScanBreadcrumb(
  message: string,
  category: string = 'scan',
  data?: Record<string, unknown>
): void {
  Sentry.addBreadcrumb({
    category,
    message,
    level: 'info',
    data,
    timestamp: Date.now() / 1000,
  });
}

/**
 * Capture GitHub API errors separately
 */
export function captureGitHubError(
  error: Error,
  operation: string,
  context?: Record<string, unknown>
): void {
  Sentry.withScope((scope) => {
    scope.setTag('integration', 'github');
    scope.setTag('operation', operation);
    scope.setContext('github', context || {});
    Sentry.captureException(error);
  });
}

/**
 * Flush Sentry events before function ends
 * Important for Edge Functions which may terminate quickly
 */
export async function flushSentry(timeout: number = 2000): Promise<boolean> {
  try {
    return await Sentry.flush(timeout);
  } catch (error) {
    console.error('Failed to flush Sentry:', error);
    return false;
  }
}

/**
 * Wrapper for async functions with automatic error capture
 */
export function withSentry<T>(
  fn: () => Promise<T>,
  operationName: string
): Promise<T> {
  return Sentry.startSpan(
    {
      name: operationName,
      op: 'function',
    },
    async () => {
      try {
        return await fn();
      } catch (error) {
        Sentry.captureException(error);
        throw error;
      }
    }
  );
}

/**
 * Create a Sentry-wrapped handler for Edge Functions
 */
export function wrapHandler(
  handler: (req: Request) => Promise<Response>
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    initSentry();

    const transaction = Sentry.startTransaction({
      name: `${req.method} ${new URL(req.url).pathname}`,
      op: 'http.server',
    });

    Sentry.getCurrentHub().configureScope((scope) => {
      scope.setSpan(transaction);
    });

    try {
      const response = await handler(req);
      transaction.setHttpStatus(response.status);
      return response;
    } catch (error) {
      transaction.setHttpStatus(500);
      Sentry.captureException(error);
      throw error;
    } finally {
      transaction.finish();
      await flushSentry();
    }
  };
}

// Export Sentry for direct access if needed
export { Sentry };
