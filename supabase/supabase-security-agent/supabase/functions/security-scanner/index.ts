/**
 * Supabase Security Scanner Edge Function
 * 
 * Scans the database for security vulnerabilities and reports them to GitHub Issues.
 * 
 * Endpoints:
 *   POST /security-scanner          - Run full scan
 *   POST /security-scanner/check    - Run specific check by ID
 *   GET  /security-scanner/status   - Get last scan status
 * 
 * Headers:
 *   Authorization: Bearer <service_role_key>
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
 * Main handler
 */
serve(async (req: Request) => {
  const url = new URL(req.url);
  const path = url.pathname.replace('/security-scanner', '');
  
  // CORS headers
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Verify authorization
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Initialize Supabase client with service role
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Route handling
    switch (path) {
      case '':
      case '/':
        if (req.method === 'POST') {
          const config = await getConfig(req);
          const result = await runFullScan(supabase, config);
          return new Response(
            JSON.stringify(result),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
        break;
      
      case '/check':
        if (req.method === 'POST') {
          const body = await req.json();
          const checkId = body.check_id;
          if (!checkId) {
            return new Response(
              JSON.stringify({ error: 'Missing check_id in request body' }),
              { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
          }
          const result = await runSingleCheck(supabase, checkId);
          return new Response(
            JSON.stringify(result),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
        break;
      
      case '/status':
        if (req.method === 'GET') {
          const status = await getLastScanStatus(supabase);
          return new Response(
            JSON.stringify(status),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
        break;
    }

    return new Response(
      JSON.stringify({ error: 'Not found' }),
      { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Scanner error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
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
 * Run all security checks
 */
async function runFullScan(
  supabase: SupabaseClient, 
  config: ScannerConfig
): Promise<ScanResult> {
  const scanId = crypto.randomUUID();
  const startedAt = new Date().toISOString();
  const vulnerabilities: Vulnerability[] = [];
  
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

    try {
      console.log(`Running check: ${check.id}`);
      const { data, error } = await supabase.rpc('exec_sql', { 
        query: check.query 
      });

      if (error) {
        // Try direct query if RPC not available
        const { data: directData, error: directError } = await supabase
          .from('_security_scan_temp')
          .select('*')
          .limit(0);
        
        // Log error but continue
        console.warn(`Check ${check.id} query error:`, error.message);
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
          vulnerabilities.push(createVulnerability(check, filteredData));
        } else {
          passedChecks++;
        }
      } else {
        passedChecks++;
      }
    } catch (err) {
      console.error(`Error running check ${check.id}:`, err);
    }
  }

  const completedAt = new Date().toISOString();
  const summary = calculateSummary(vulnerabilities);

  const result: ScanResult = {
    scan_id: scanId,
    project_ref: Deno.env.get('SUPABASE_URL')?.split('//')[1]?.split('.')[0] || 'unknown',
    started_at: startedAt,
    completed_at: completedAt,
    duration_ms: new Date(completedAt).getTime() - new Date(startedAt).getTime(),
    total_checks: checksToRun.length,
    passed_checks: passedChecks,
    failed_checks: failedChecks,
    vulnerabilities,
    summary
  };

  // Store scan result
  await storeScanResult(supabase, result);

  // Send notifications
  if (config.notifications.github_issues && vulnerabilities.length > 0) {
    await createGitHubIssues(vulnerabilities);
  }

  if (config.notifications.slack_webhook && vulnerabilities.length > 0) {
    await sendSlackNotification(config.notifications.slack_webhook, result);
  }

  return result;
}

/**
 * Run a single check by ID
 */
async function runSingleCheck(
  supabase: SupabaseClient, 
  checkId: string
): Promise<Vulnerability | { message: string }> {
  const check = getCheckById(checkId);
  
  if (!check) {
    throw new Error(`Check not found: ${checkId}`);
  }

  const { data, error } = await supabase.rpc('exec_sql', { 
    query: check.query 
  });

  if (error) {
    throw new Error(`Query error: ${error.message}`);
  }

  if (data && data.length > 0) {
    return createVulnerability(check, data);
  }

  return { message: `Check ${checkId} passed - no vulnerabilities found` };
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
    // Create table if not exists (first run)
    await supabase.rpc('exec_sql', {
      query: `
        CREATE TABLE IF NOT EXISTS _security_scans (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          scan_id TEXT NOT NULL,
          result JSONB NOT NULL,
          created_at TIMESTAMPTZ DEFAULT NOW()
        );
      `
    });

    await supabase.rpc('exec_sql', {
      query: `
        INSERT INTO _security_scans (scan_id, result)
        VALUES ('${result.scan_id}', '${JSON.stringify(result)}'::jsonb);
      `
    });
  } catch (err) {
    console.warn('Could not store scan result:', err);
  }
}

/**
 * Get last scan status
 */
async function getLastScanStatus(supabase: SupabaseClient): Promise<ScanResult | null> {
  try {
    const { data, error } = await supabase.rpc('exec_sql', {
      query: `
        SELECT result FROM _security_scans 
        ORDER BY created_at DESC 
        LIMIT 1;
      `
    });

    if (error || !data || data.length === 0) {
      return null;
    }

    return data[0].result as ScanResult;
  } catch {
    return null;
  }
}

/**
 * Create GitHub Issues for vulnerabilities
 */
async function createGitHubIssues(vulnerabilities: Vulnerability[]): Promise<void> {
  const githubToken = Deno.env.get('GITHUB_TOKEN');
  const githubOwner = Deno.env.get('GITHUB_OWNER');
  const githubRepo = Deno.env.get('GITHUB_REPO');

  if (!githubToken || !githubOwner || !githubRepo) {
    console.warn('GitHub configuration incomplete, skipping issue creation');
    return;
  }

  // Group by severity and create one issue per high/critical vulnerability
  // or batch medium/low into a single issue
  const criticalHigh = vulnerabilities.filter(v => 
    v.severity === 'critical' || v.severity === 'high'
  );
  const mediumLow = vulnerabilities.filter(v => 
    v.severity === 'medium' || v.severity === 'low'
  );

  // Create individual issues for critical/high
  for (const vuln of criticalHigh) {
    const issue = formatGitHubIssue(vuln);
    await createGitHubIssue(githubToken, githubOwner, githubRepo, issue);
  }

  // Batch medium/low into one issue
  if (mediumLow.length > 0) {
    const batchIssue = formatBatchGitHubIssue(mediumLow);
    await createGitHubIssue(githubToken, githubOwner, githubRepo, batchIssue);
  }
}

/**
 * Format single vulnerability as GitHub issue
 */
function formatGitHubIssue(vuln: Vulnerability): GitHubIssuePayload {
  const affectedList = vuln.affected_objects
    .map(obj => `- \`${obj.schema}.${obj.name}\` (${obj.type})${obj.details ? `: ${obj.details}` : ''}`)
    .join('\n');

  const body = `## 🔒 Security Vulnerability Detected

**Check:** ${vuln.check_name}
**Severity:** ${vuln.severity.toUpperCase()}
**Category:** ${vuln.category}
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
function formatBatchGitHubIssue(vulnerabilities: Vulnerability[]): GitHubIssuePayload {
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
    } else {
      const created = await response.json();
      console.log(`Created GitHub issue #${created.number}: ${issue.title}`);
    }
  } catch (err) {
    console.error('Error creating GitHub issue:', err);
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
  } catch (err) {
    console.error('Error sending Slack notification:', err);
  }
}
