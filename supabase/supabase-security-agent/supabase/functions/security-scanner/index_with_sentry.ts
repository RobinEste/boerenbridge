/**
 * Supabase Security Scanner Edge Function (with Sentry)
 * 
 * Scans the database for security vulnerabilities and reports them to GitHub Issues.
 * Now with full Sentry integration for error tracking and performance monitoring.
 * 
 * Endpoints:
 *   POST /security-scanner          - Run full scan
 *   POST /security-scanner/check    - Run specific check by ID
 *   GET  /security-scanner/status   - Get last scan status
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { SECURITY_CHECKS, getCheckById } from './checks.ts';
import { 
  Vulnerability, 
  ScanResult, 
  ScanSummary, 
  AffectedObject,
  Severity,
  GitHubIssuePayload,
  ScannerConfig
} from './types.ts';
import {
  initSentry,
  startScanTransaction,
  startCheckSpan,
  setScanContext,
  recordVulnerability,
  recordScanMetrics,
  addScanBreadcrumb,
  captureError,
  captureGitHubError,
  flushSentry,
  Sentry
} from './sentry.ts';

// Configuration
const GITHUB_API_URL = 'https://api.github.com';
const SEVERITY_ORDER: Record<Severity, number> = {
  critical: 5,
  high: 4,
  medium: 3,
  low: 2,
  info: 1
};

// Default configuration
const DEFAULT_CONFIG: ScannerConfig = {
  enabled_checks: 'all',
  severity_threshold: 'low',
  excluded_tables: ['_prisma_migrations', 'schema_migrations'],
  excluded_schemas: ['pg_catalog', 'information_schema', 'pg_toast'],
  notifications: {
    github_issues: true,
    slack_webhook: null
  }
};

/**
 * Main handler with Sentry wrapper
 */
serve(async (req: Request) => {
  // Initialize Sentry at the start of each request
  initSentry();
  
  const url = new URL(req.url);
  const path = url.pathname.replace('/security-scanner', '');
  
  // Start a Sentry transaction for this request
  const transaction = Sentry.startTransaction({
    name: `${req.method} /security-scanner${path}`,
    op: 'http.server',
  });
  
  Sentry.getCurrentHub().configureScope((scope) => {
    scope.setSpan(transaction);
    scope.setTag('endpoint', path || '/');
    scope.setTag('method', req.method);
  });
  
  // CORS headers
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };

  if (req.method === 'OPTIONS') {
    transaction.setHttpStatus(200);
    transaction.finish();
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Verify authorization
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      transaction.setHttpStatus(401);
      addScanBreadcrumb('Authorization failed: missing header', 'auth');
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Initialize Supabase client with service role
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);
    
    addScanBreadcrumb('Supabase client initialized', 'setup');

    let response: Response;

    // Route handling
    switch (path) {
      case '':
      case '/':
        if (req.method === 'POST') {
          const config = await getConfig(req);
          const result = await runFullScan(supabase, config, transaction);
          transaction.setHttpStatus(200);
          response = new Response(
            JSON.stringify(result),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        } else {
          transaction.setHttpStatus(405);
          response = new Response(
            JSON.stringify({ error: 'Method not allowed' }),
            { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
        break;
      
      case '/check':
        if (req.method === 'POST') {
          const body = await req.json();
          const checkId = body.check_id;
          if (!checkId) {
            transaction.setHttpStatus(400);
            response = new Response(
              JSON.stringify({ error: 'Missing check_id in request body' }),
              { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
          } else {
            const result = await runSingleCheck(supabase, checkId, transaction);
            transaction.setHttpStatus(200);
            response = new Response(
              JSON.stringify(result),
              { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
          }
        } else {
          transaction.setHttpStatus(405);
          response = new Response(
            JSON.stringify({ error: 'Method not allowed' }),
            { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
        break;
      
      case '/status':
        if (req.method === 'GET') {
          const status = await getLastScanStatus(supabase);
          transaction.setHttpStatus(200);
          response = new Response(
            JSON.stringify(status),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        } else {
          transaction.setHttpStatus(405);
          response = new Response(
            JSON.stringify({ error: 'Method not allowed' }),
            { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
        break;
      
      default:
        transaction.setHttpStatus(404);
        response = new Response(
          JSON.stringify({ error: 'Not found' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }

    transaction.finish();
    await flushSentry();
    return response;

  } catch (error) {
    console.error('Scanner error:', error);
    transaction.setHttpStatus(500);
    
    // Capture the error in Sentry with full context
    const eventId = captureError(error as Error, {
      endpoint: path,
      method: req.method,
    });
    
    transaction.finish();
    await flushSentry();
    
    return new Response(
      JSON.stringify({ 
        error: (error as Error).message,
        sentry_event_id: eventId // Include for debugging
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});

/**
 * Get configuration from request or use defaults
 */
async function getConfig(req: Request): Promise<ScannerConfig> {
  try {
    const body = await req.json();
    return { ...DEFAULT_CONFIG, ...body.config };
  } catch {
    return DEFAULT_CONFIG;
  }
}

/**
 * Run all security checks with Sentry instrumentation
 */
async function runFullScan(
  supabase: SupabaseClient, 
  config: ScannerConfig,
  parentTransaction: Sentry.Transaction
): Promise<ScanResult> {
  const scanId = crypto.randomUUID();
  const startedAt = new Date().toISOString();
  const vulnerabilities: Vulnerability[] = [];
  
  // Set Sentry context for this scan
  setScanContext({
    scan_id: scanId,
    project_ref: Deno.env.get('SUPABASE_URL')?.split('//')[1]?.split('.')[0] || 'unknown',
    checks_count: SECURITY_CHECKS.length,
    config: config as Record<string, unknown>,
  });
  
  addScanBreadcrumb(`Starting security scan: ${scanId}`, 'scan', { config });
  
  // Filter checks based on config
  const checksToRun = config.enabled_checks === 'all' 
    ? SECURITY_CHECKS 
    : SECURITY_CHECKS.filter(c => (config.enabled_checks as string[]).includes(c.id));

  let passedChecks = 0;
  let failedChecks = 0;

  for (const check of checksToRun) {
    // Skip if below severity threshold
    if (SEVERITY_ORDER[check.severity] < SEVERITY_ORDER[config.severity_threshold]) {
      passedChecks++;
      continue;
    }

    // Create a Sentry span for this check
    const checkSpan = startCheckSpan(parentTransaction, check.id, check.name);
    
    try {
      addScanBreadcrumb(`Running check: ${check.id}`, 'check');
      
      const { data, error } = await supabase.rpc('exec_sql', { 
        query: check.query 
      });

      if (error) {
        // Log error but continue with other checks
        console.warn(`Check ${check.id} query error:`, error.message);
        addScanBreadcrumb(`Check failed: ${check.id}`, 'check', { error: error.message });
        
        if (checkSpan) {
          checkSpan.setStatus('internal_error');
          checkSpan.setData('error', error.message);
        }
        continue;
      }

      if (data && data.length > 0) {
        // Filter excluded tables/schemas
        const filteredData = data.filter((row: Record<string, unknown>) => {
          const schema = row.schemaname as string || row.schema as string;
          const table = row.tablename as string || row.table_name as string;
          
          if (schema && config.excluded_schemas.includes(schema)) return false;
          if (table && config.excluded_tables.includes(table)) return false;
          
          return true;
        });

        if (filteredData.length > 0) {
          failedChecks++;
          const vuln = createVulnerability(check, filteredData);
          vulnerabilities.push(vuln);
          
          // Record vulnerability in Sentry
          recordVulnerability(
            check.id,
            check.name,
            check.severity,
            vuln.affected_objects,
            scanId
          );
          
          if (checkSpan) {
            checkSpan.setStatus('ok');
            checkSpan.setData('findings_count', filteredData.length);
            checkSpan.setData('severity', check.severity);
          }
          
          addScanBreadcrumb(
            `Vulnerability found: ${check.name}`, 
            'vulnerability',
            { severity: check.severity, count: filteredData.length }
          );
        } else {
          passedChecks++;
          if (checkSpan) {
            checkSpan.setStatus('ok');
            checkSpan.setData('result', 'passed');
          }
        }
      } else {
        passedChecks++;
        if (checkSpan) {
          checkSpan.setStatus('ok');
          checkSpan.setData('result', 'passed');
        }
      }
    } catch (err) {
      console.error(`Error running check ${check.id}:`, err);
      captureError(err as Error, { check_id: check.id, check_name: check.name });
      
      if (checkSpan) {
        checkSpan.setStatus('internal_error');
      }
    } finally {
      if (checkSpan) {
        checkSpan.finish();
      }
    }
  }

  const completedAt = new Date().toISOString();
  const summary = calculateSummary(vulnerabilities);
  const durationMs = new Date(completedAt).getTime() - new Date(startedAt).getTime();

  // Record scan metrics in Sentry
  recordScanMetrics(scanId, {
    duration_ms: durationMs,
    total_checks: checksToRun.length,
    passed_checks: passedChecks,
    failed_checks: failedChecks,
    critical_count: summary.critical,
    high_count: summary.high,
    medium_count: summary.medium,
    low_count: summary.low,
  });

  const result: ScanResult = {
    scan_id: scanId,
    project_ref: Deno.env.get('SUPABASE_URL')?.split('//')[1]?.split('.')[0] || 'unknown',
    started_at: startedAt,
    completed_at: completedAt,
    duration_ms: durationMs,
    total_checks: checksToRun.length,
    passed_checks: passedChecks,
    failed_checks: failedChecks,
    vulnerabilities,
    summary
  };

  // Store scan result
  const storeSpan = parentTransaction.startChild({ op: 'db', description: 'Store scan result' });
  await storeScanResult(supabase, result);
  storeSpan.finish();

  // Send notifications
  if (config.notifications.github_issues && vulnerabilities.length > 0) {
    const githubSpan = parentTransaction.startChild({ op: 'http', description: 'Create GitHub issues' });
    await createGitHubIssues(vulnerabilities, scanId);
    githubSpan.finish();
  }

  if (config.notifications.slack_webhook && vulnerabilities.length > 0) {
    const slackSpan = parentTransaction.startChild({ op: 'http', description: 'Send Slack notification' });
    await sendSlackNotification(config.notifications.slack_webhook, result);
    slackSpan.finish();
  }

  addScanBreadcrumb(
    `Scan completed: ${failedChecks} vulnerabilities found`,
    'scan',
    { scan_id: scanId, duration_ms: durationMs }
  );

  return result;
}

/**
 * Run a single check by ID
 */
async function runSingleCheck(
  supabase: SupabaseClient, 
  checkId: string,
  transaction: Sentry.Transaction
): Promise<Vulnerability | { message: string }> {
  const check = getCheckById(checkId);
  
  if (!check) {
    throw new Error(`Check not found: ${checkId}`);
  }

  const span = transaction.startChild({
    op: 'security-check',
    description: check.name,
  });

  try {
    const { data, error } = await supabase.rpc('exec_sql', { 
      query: check.query 
    });

    if (error) {
      span.setStatus('internal_error');
      throw new Error(`Query error: ${error.message}`);
    }

    if (data && data.length > 0) {
      span.setStatus('ok');
      span.setData('findings_count', data.length);
      return createVulnerability(check, data);
    }

    span.setStatus('ok');
    span.setData('result', 'passed');
    return { message: `Check ${checkId} passed - no vulnerabilities found` };
  } finally {
    span.finish();
  }
}

/**
 * Create vulnerability object from check results
 */
function createVulnerability(
  check: typeof SECURITY_CHECKS[0], 
  results: Record<string, unknown>[]
): Vulnerability {
  const affectedObjects: AffectedObject[] = results.map(row => ({
    type: determineObjectType(row),
    schema: (row.schemaname || row.schema || 'public') as string,
    name: (row.tablename || row.table_name || row.viewname || row.function_name || row.bucket_name || 'unknown') as string,
    details: row.issue as string || row.column_name as string
  }));

  return {
    check_id: check.id,
    check_name: check.name,
    severity: check.severity,
    category: check.category,
    description: check.description,
    affected_objects: affectedObjects,
    remediation: check.remediation,
    raw_query_result: results,
    detected_at: new Date().toISOString(),
    metadata: {
      documentation_url: check.documentation_url
    }
  };
}

/**
 * Determine object type from query result
 */
function determineObjectType(row: Record<string, unknown>): AffectedObject['type'] {
  if (row.bucket_name || row.bucket_id) return 'bucket';
  if (row.viewname || row.matviewname) return 'view';
  if (row.function_name || row.proname) return 'function';
  if (row.policyname) return 'policy';
  if (row.extname) return 'extension';
  return 'table';
}

/**
 * Calculate severity summary
 */
function calculateSummary(vulnerabilities: Vulnerability[]): ScanSummary {
  return {
    critical: vulnerabilities.filter(v => v.severity === 'critical').length,
    high: vulnerabilities.filter(v => v.severity === 'high').length,
    medium: vulnerabilities.filter(v => v.severity === 'medium').length,
    low: vulnerabilities.filter(v => v.severity === 'low').length,
    info: vulnerabilities.filter(v => v.severity === 'info').length
  };
}

/**
 * Store scan result in database
 */
async function storeScanResult(supabase: SupabaseClient, result: ScanResult): Promise<void> {
  try {
    await supabase.rpc('exec_sql', {
      query: `
        INSERT INTO _security.scans (scan_id, project_ref, started_at, completed_at, duration_ms, 
          total_checks, passed_checks, failed_checks, summary, vulnerabilities)
        VALUES (
          '${result.scan_id}',
          '${result.project_ref}',
          '${result.started_at}',
          '${result.completed_at}',
          ${result.duration_ms},
          ${result.total_checks},
          ${result.passed_checks},
          ${result.failed_checks},
          '${JSON.stringify(result.summary)}'::jsonb,
          '${JSON.stringify(result.vulnerabilities)}'::jsonb
        );
      `
    });
  } catch (err) {
    console.warn('Could not store scan result:', err);
    captureError(err as Error, { operation: 'store_scan_result', scan_id: result.scan_id });
  }
}

/**
 * Get last scan status
 */
async function getLastScanStatus(supabase: SupabaseClient): Promise<ScanResult | null> {
  try {
    const { data, error } = await supabase.rpc('exec_sql', {
      query: `
        SELECT scan_id, project_ref, started_at, completed_at, duration_ms,
               total_checks, passed_checks, failed_checks, summary, vulnerabilities
        FROM _security.scans 
        ORDER BY created_at DESC 
        LIMIT 1;
      `
    });

    if (error || !data || data.length === 0) {
      return null;
    }

    return data[0] as ScanResult;
  } catch {
    return null;
  }
}

/**
 * Create GitHub Issues for vulnerabilities
 */
async function createGitHubIssues(vulnerabilities: Vulnerability[], scanId: string): Promise<void> {
  const githubToken = Deno.env.get('GITHUB_TOKEN');
  const githubOwner = Deno.env.get('GITHUB_OWNER');
  const githubRepo = Deno.env.get('GITHUB_REPO');

  if (!githubToken || !githubOwner || !githubRepo) {
    console.warn('GitHub configuration incomplete, skipping issue creation');
    addScanBreadcrumb('GitHub issues skipped: configuration incomplete', 'github');
    return;
  }

  // Group by severity
  const criticalHigh = vulnerabilities.filter(v => 
    v.severity === 'critical' || v.severity === 'high'
  );
  const mediumLow = vulnerabilities.filter(v => 
    v.severity === 'medium' || v.severity === 'low'
  );

  // Create individual issues for critical/high
  for (const vuln of criticalHigh) {
    const issue = formatGitHubIssue(vuln, scanId);
    await createGitHubIssue(githubToken, githubOwner, githubRepo, issue);
  }

  // Batch medium/low into one issue
  if (mediumLow.length > 0) {
    const batchIssue = formatBatchGitHubIssue(mediumLow, scanId);
    await createGitHubIssue(githubToken, githubOwner, githubRepo, batchIssue);
  }
}

/**
 * Format single vulnerability as GitHub issue
 */
function formatGitHubIssue(vuln: Vulnerability, scanId: string): GitHubIssuePayload {
  const affectedList = vuln.affected_objects
    .map(obj => `- \`${obj.schema}.${obj.name}\` (${obj.type})${obj.details ? `: ${obj.details}` : ''}`)
    .join('\n');

  const body = `## 🔒 Security Vulnerability Detected

**Check:** ${vuln.check_name}
**Severity:** ${vuln.severity.toUpperCase()}
**Category:** ${vuln.category}
**Scan ID:** \`${scanId}\`
**Detected:** ${vuln.detected_at}

### Description

${vuln.description}

### Affected Objects

${affectedList}

### Recommended Remediation

\`\`\`sql
${vuln.remediation.trim()}
\`\`\`

### Additional Information

${vuln.metadata?.documentation_url ? `📚 [Documentation](${vuln.metadata.documentation_url})` : ''}

---

<details>
<summary>Raw Query Result</summary>

\`\`\`json
${JSON.stringify(vuln.raw_query_result, null, 2)}
\`\`\`

</details>

---
*This issue was automatically created by the Supabase Security Scanner.*
*Label this issue with \`security-agent-processed\` after the Claude agent has reviewed it.*
`;

  return {
    title: `🔒 [${vuln.severity.toUpperCase()}] ${vuln.check_name}`,
    body,
    labels: ['security', 'automated', `severity:${vuln.severity}`, vuln.category]
  };
}

/**
 * Format batch of vulnerabilities as single GitHub issue
 */
function formatBatchGitHubIssue(vulnerabilities: Vulnerability[], scanId: string): GitHubIssuePayload {
  const vulnList = vulnerabilities.map(vuln => {
    const affected = vuln.affected_objects
      .slice(0, 3)
      .map(obj => `\`${obj.schema}.${obj.name}\``)
      .join(', ');
    const more = vuln.affected_objects.length > 3 
      ? ` (+${vuln.affected_objects.length - 3} more)` 
      : '';
    
    return `### ${vuln.check_name}
- **Severity:** ${vuln.severity}
- **Affected:** ${affected}${more}
- **Description:** ${vuln.description}`;
  }).join('\n\n');

  const body = `## 🔒 Security Scan: Multiple Findings

**Scan ID:** \`${scanId}\`

The security scanner detected **${vulnerabilities.length}** medium/low severity issues.

${vulnList}

---

<details>
<summary>Full Vulnerability Details</summary>

\`\`\`json
${JSON.stringify(vulnerabilities, null, 2)}
\`\`\`

</details>

---
*This issue was automatically created by the Supabase Security Scanner.*
`;

  return {
    title: `🔒 Security Scan: ${vulnerabilities.length} findings (medium/low)`,
    body,
    labels: ['security', 'automated', 'severity:medium', 'batch']
  };
}

/**
 * Create GitHub issue via API
 */
async function createGitHubIssue(
  token: string, 
  owner: string, 
  repo: string, 
  issue: GitHubIssuePayload
): Promise<void> {
  try {
    const response = await fetch(
      `${GITHUB_API_URL}/repos/${owner}/${repo}/issues`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Accept': 'application/vnd.github+json',
          'Content-Type': 'application/json',
          'X-GitHub-Api-Version': '2022-11-28'
        },
        body: JSON.stringify(issue)
      }
    );

    if (!response.ok) {
      const error = await response.text();
      console.error('Failed to create GitHub issue:', error);
      captureGitHubError(new Error(`GitHub API error: ${response.status}`), 'create_issue', {
        status: response.status,
        error,
      });
    } else {
      const created = await response.json();
      console.log(`Created GitHub issue #${created.number}: ${issue.title}`);
      addScanBreadcrumb(`Created GitHub issue #${created.number}`, 'github');
    }
  } catch (err) {
    console.error('Error creating GitHub issue:', err);
    captureGitHubError(err as Error, 'create_issue');
  }
}

/**
 * Send Slack notification
 */
async function sendSlackNotification(webhookUrl: string, result: ScanResult): Promise<void> {
  const emoji = result.summary.critical > 0 ? '🚨' : 
                result.summary.high > 0 ? '⚠️' : 
                result.summary.medium > 0 ? '🔶' : '✅';

  const message = {
    blocks: [
      {
        type: 'header',
        text: {
          type: 'plain_text',
          text: `${emoji} Supabase Security Scan Complete`,
          emoji: true
        }
      },
      {
        type: 'section',
        fields: [
          { type: 'mrkdwn', text: `*Critical:* ${result.summary.critical}` },
          { type: 'mrkdwn', text: `*High:* ${result.summary.high}` },
          { type: 'mrkdwn', text: `*Medium:* ${result.summary.medium}` },
          { type: 'mrkdwn', text: `*Low:* ${result.summary.low}` }
        ]
      },
      {
        type: 'context',
        elements: [
          {
            type: 'mrkdwn',
            text: `Scan ID: \`${result.scan_id}\` | Duration: ${result.duration_ms}ms`
          }
        ]
      }
    ]
  };

  try {
    await fetch(webhookUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(message)
    });
    addScanBreadcrumb('Slack notification sent', 'notification');
  } catch (err) {
    console.error('Error sending Slack notification:', err);
    captureError(err as Error, { operation: 'slack_notification' });
  }
}
