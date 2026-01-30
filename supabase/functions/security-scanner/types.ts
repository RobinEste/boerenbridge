/**
 * Security Scanner Types
 *
 * Type definitions for the Supabase security vulnerability scanner
 */

export type Severity = 'critical' | 'high' | 'medium' | 'low' | 'info';

export interface SecurityCheck {
  id: string;
  name: string;
  description: string;
  severity: Severity;
  category: SecurityCategory;
  query: string;
  remediation: string;
  documentation_url?: string;
}

export type SecurityCategory =
  | 'rls'
  | 'authentication'
  | 'authorization'
  | 'data_exposure'
  | 'configuration'
  | 'performance'
  | 'extensions';

export interface Vulnerability {
  check_id: string;
  check_name: string;
  severity: Severity;
  category: SecurityCategory;
  description: string;
  affected_objects: AffectedObject[];
  remediation: string;
  raw_query_result: Record<string, unknown>[];
  detected_at: string;
  metadata?: Record<string, unknown>;
}

export interface AffectedObject {
  type: 'table' | 'view' | 'function' | 'policy' | 'extension' | 'schema' | 'role' | 'bucket';
  schema: string;
  name: string;
  details?: string;
}

export interface ScanResult {
  scan_id: string;
  project_ref: string;
  started_at: string;
  completed_at: string;
  duration_ms: number;
  total_checks: number;
  passed_checks: number;
  failed_checks: number;
  vulnerabilities: Vulnerability[];
  summary: ScanSummary;
}

export interface ScanSummary {
  critical: number;
  high: number;
  medium: number;
  low: number;
  info: number;
}

export interface GitHubIssuePayload {
  title: string;
  body: string;
  labels: string[];
  assignees?: string[];
}

export interface ScannerConfig {
  enabled_checks: string[] | 'all';
  severity_threshold: Severity;
  excluded_tables: string[];
  excluded_schemas: string[];
  notifications: {
    github_issues: boolean;
    slack_webhook: string | null;
  };
}

export interface AgentConfig {
  model: string;
  auto_create_pr: boolean;
  require_approval: boolean;
  max_tokens: number;
  include_tests: boolean;
}

// GitHub API types
export interface GitHubIssue {
  number: number;
  title: string;
  body: string;
  labels: GitHubLabel[];
  state: 'open' | 'closed';
  created_at: string;
  updated_at: string;
}

export interface GitHubLabel {
  name: string;
  color: string;
  description?: string;
}

// Database query result types
export interface TableInfo {
  schemaname: string;
  tablename: string;
  rowsecurity: boolean;
}

export interface PolicyInfo {
  schemaname: string;
  tablename: string;
  policyname: string;
  permissive: string;
  roles: string[];
  cmd: string;
  qual: string;
  with_check: string;
}

export interface ExtensionInfo {
  extname: string;
  extversion: string;
  extnamespace: string;
}

export interface FunctionInfo {
  schema: string;
  name: string;
  security_definer: boolean;
  search_path: string;
}
