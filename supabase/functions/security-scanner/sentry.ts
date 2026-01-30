/**
 * Sentry Hybrid Client for Security Scanner (Deno 1.x compatible)
 *
 * Uses the Sentry Envelope API for error capture (no SDK dependency).
 * Transactions/spans remain no-ops since performance monitoring requires the SDK.
 *
 * Graceful degradation: if SENTRY_DSN is not set, all functions are no-ops.
 */

// --- Internal state ---

interface ParsedDsn {
  publicKey: string;
  host: string;
  projectId: string;
  envelopeUrl: string;
  dsn: string;
}

interface BreadcrumbEntry {
  type?: string;
  category?: string;
  message?: string;
  data?: Record<string, unknown>;
  level?: string;
  timestamp?: number;
}

interface ScopeData {
  tags: Record<string, string>;
  contexts: Record<string, Record<string, unknown>>;
  extra: Record<string, unknown>;
  user: Record<string, unknown> | null;
  level: string | null;
  fingerprint: string[] | null;
}

const MAX_BREADCRUMBS = 50;
const MAX_DATA_SIZE = 1024;

let parsedDsn: ParsedDsn | null = null;
let isEnabled = false;
const breadcrumbBuffer: BreadcrumbEntry[] = [];
const pendingFetches: Promise<unknown>[] = [];
const scopeData: ScopeData = {
  tags: {},
  contexts: {},
  extra: {},
  user: null,
  level: null,
  fingerprint: null,
};

// --- Sanitization ---

const SENSITIVE_PATTERNS = [
  /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g, // JWT
  /sk-[A-Za-z0-9]{20,}/g,                                             // OpenAI-style keys
  /ghp_[A-Za-z0-9]{36,}/g,                                            // GitHub PAT
  /sk-ant-[A-Za-z0-9_-]{20,}/g,                                       // Anthropic keys
  /sbp_[A-Za-z0-9]{40,}/g,                                            // Supabase keys
  /(?<=:\/\/[^:]+:)[^@]+(?=@)/g,                                      // Passwords in URLs
];

function sanitizeString(value: string): string {
  let result = value;
  for (const pattern of SENSITIVE_PATTERNS) {
    result = result.replace(pattern, '[REDACTED]');
  }
  return result;
}

function sanitizeValue(value: unknown): unknown {
  if (typeof value === 'string') return sanitizeString(value);
  if (Array.isArray(value)) return value.map(sanitizeValue);
  if (value !== null && typeof value === 'object') {
    const sanitized: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      sanitized[k] = sanitizeValue(v);
    }
    return sanitized;
  }
  return value;
}

function truncateData(data: Record<string, unknown>): Record<string, unknown> {
  const json = JSON.stringify(data);
  if (json.length <= MAX_DATA_SIZE) return data;
  const truncated: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(data)) {
    const valStr = JSON.stringify(v);
    if (valStr.length > 256) {
      truncated[k] = typeof v === 'string'
        ? v.slice(0, 253) + '...'
        : '[truncated]';
    } else {
      truncated[k] = v;
    }
  }
  return truncated;
}

// --- DSN parsing ---

function parseDsn(dsn: string): ParsedDsn | null {
  try {
    const url = new URL(dsn);
    const publicKey = url.username;
    const host = url.hostname + (url.port ? `:${url.port}` : '');
    const projectId = url.pathname.replace('/', '');
    const protocol = url.protocol;

    if (!publicKey || !projectId) return null;

    const envelopeUrl =
      `${protocol}//${host}/api/${projectId}/envelope/?sentry_key=${publicKey}&sentry_version=7`;

    return { publicKey, host, projectId, envelopeUrl, dsn };
  } catch {
    return null;
  }
}

// --- UUID generation ---

function generateEventId(): string {
  return crypto.randomUUID().replace(/-/g, '');
}

// --- Envelope construction ---

function buildErrorEnvelope(
  error: Error,
  extra?: Record<string, unknown>,
): string {
  const eventId = generateEventId();
  const now = new Date();

  const header = JSON.stringify({
    event_id: eventId,
    dsn: parsedDsn!.dsn,
    sent_at: now.toISOString(),
  });

  const itemHeader = JSON.stringify({ type: 'event' });

  const frames = parseStacktrace(error);

  const event: Record<string, unknown> = {
    event_id: eventId,
    timestamp: now.getTime() / 1000,
    level: 'error',
    platform: 'javascript',
    server_name: 'supabase-edge-function',
    environment: Deno.env.get('SENTRY_ENVIRONMENT') || 'production',
    exception: {
      values: [
        {
          type: error.name || 'Error',
          value: sanitizeString(error.message || 'Unknown error'),
          stacktrace: frames.length > 0 ? { frames } : undefined,
        },
      ],
    },
    breadcrumbs: {
      values: breadcrumbBuffer.map((b) => ({
        ...b,
        data: b.data ? sanitizeValue(b.data) : undefined,
      })),
    },
    tags: { ...scopeData.tags },
    contexts: {
      ...scopeData.contexts,
      runtime: { name: 'deno', version: Deno.version?.deno || 'unknown' },
    },
    extra: {
      ...scopeData.extra,
      ...(extra ? sanitizeValue(extra) as Record<string, unknown> : {}),
    },
  };

  if (scopeData.user) event.user = scopeData.user;
  if (scopeData.fingerprint) event.fingerprint = scopeData.fingerprint;

  return `${header}\n${itemHeader}\n${JSON.stringify(event)}\n`;
}

function buildMessageEnvelope(
  message: string,
  level: string,
  extra?: Record<string, unknown>,
): string {
  const eventId = generateEventId();
  const now = new Date();

  const header = JSON.stringify({
    event_id: eventId,
    dsn: parsedDsn!.dsn,
    sent_at: now.toISOString(),
  });

  const itemHeader = JSON.stringify({ type: 'event' });

  const event: Record<string, unknown> = {
    event_id: eventId,
    timestamp: now.getTime() / 1000,
    level,
    platform: 'javascript',
    server_name: 'supabase-edge-function',
    environment: Deno.env.get('SENTRY_ENVIRONMENT') || 'production',
    message: { formatted: sanitizeString(message) },
    breadcrumbs: {
      values: breadcrumbBuffer.map((b) => ({
        ...b,
        data: b.data ? sanitizeValue(b.data) : undefined,
      })),
    },
    tags: { ...scopeData.tags },
    contexts: {
      ...scopeData.contexts,
      runtime: { name: 'deno', version: Deno.version?.deno || 'unknown' },
    },
    extra: {
      ...scopeData.extra,
      ...(extra ? sanitizeValue(extra) as Record<string, unknown> : {}),
    },
  };

  if (scopeData.user) event.user = scopeData.user;

  return `${header}\n${itemHeader}\n${JSON.stringify(event)}\n`;
}

// --- Stack trace parsing ---

interface StackFrame {
  filename?: string;
  function?: string;
  lineno?: number;
  colno?: number;
  in_app?: boolean;
}

function parseStacktrace(error: Error): StackFrame[] {
  if (!error.stack) return [];

  const frames: StackFrame[] = [];
  const lines = error.stack.split('\n');

  for (const line of lines) {
    const match = line.match(/^\s+at\s+(?:(.+?)\s+\()?(.+?):(\d+):(\d+)\)?$/);
    if (match) {
      frames.push({
        function: match[1] || '<anonymous>',
        filename: match[2],
        lineno: parseInt(match[3], 10),
        colno: parseInt(match[4], 10),
        in_app: !match[2]?.includes('node_modules') && !match[2]?.includes('deno:'),
      });
    }
  }

  // Sentry expects frames in reverse order (oldest first)
  return frames.reverse();
}

// --- Send envelope ---

function sendEnvelope(envelope: string): void {
  if (!isEnabled || !parsedDsn) return;

  const promise = fetch(parsedDsn.envelopeUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-sentry-envelope' },
    body: envelope,
  }).catch((err) => {
    console.warn('Sentry envelope send failed:', err.message);
  });

  pendingFetches.push(promise);
}

// --- No-op span/transaction ---

interface Span {
  setStatus: (s: string) => void;
  setData: (k: string, v: unknown) => void;
  setHttpStatus: (c: number) => void;
  finish: () => void;
  startChild: (opts: Record<string, unknown>) => Span;
}

const noopSpan: Span = {
  setStatus: (_s: string) => {},
  setData: (_k: string, _v: unknown) => {},
  setHttpStatus: (_c: number) => {},
  finish: () => {},
  startChild: (_opts: Record<string, unknown>) => noopSpan,
};

// --- Sentry namespace (type-only, for Sentry.Transaction in index.ts) ---

// deno-lint-ignore no-namespace
export namespace Sentry {
  export type Transaction = Span;
}

// --- Sentry runtime object (merged with namespace via declaration merging) ---

// deno-lint-ignore no-redeclare
export const Sentry = {
  startTransaction: (_opts: Record<string, unknown>): Span => noopSpan,
  getCurrentHub: () => ({
    configureScope: (
      fn: (scope: Record<string, (...args: unknown[]) => void>) => void,
    ) => {
      fn({
        setSpan: () => {},
        setTag: (key: unknown, value: unknown) => {
          scopeData.tags[key as string] = value as string;
        },
      });
    },
  }),
  configureScope: (
    fn: (scope: Record<string, (...args: unknown[]) => void>) => void,
  ) => {
    fn({
      setTag: (key: unknown, value: unknown) => {
        scopeData.tags[key as string] = value as string;
      },
      setContext: (key: unknown, data: unknown) => {
        scopeData.contexts[key as string] = data as Record<string, unknown>;
      },
      setExtra: (key: unknown, value: unknown) => {
        scopeData.extra[key as string] = value as Record<string, unknown>[string];
      },
    });
  },
  withScope: (
    fn: (scope: Record<string, (...args: unknown[]) => void>) => void,
  ) => {
    fn({
      setLevel: (level: unknown) => {
        scopeData.level = level as string;
      },
      setContext: (key: unknown, data: unknown) => {
        scopeData.contexts[key as string] = data as Record<string, unknown>;
      },
      setTag: (key: unknown, value: unknown) => {
        scopeData.tags[key as string] = value as string;
      },
      setFingerprint: (fp: unknown) => {
        scopeData.fingerprint = fp as string[];
      },
    });
  },
  captureMessage: (msg: string, level?: string) => {
    if (!isEnabled) return;
    const envelope = buildMessageEnvelope(msg, level || 'info');
    sendEnvelope(envelope);
  },
  captureException: (err: unknown, _opts?: unknown): string => {
    if (!isEnabled) return 'disabled';
    const error = err instanceof Error ? err : new Error(String(err));
    const envelope = buildErrorEnvelope(error);
    sendEnvelope(envelope);
    return generateEventId();
  },
  addBreadcrumb: (b: Record<string, unknown>) => {
    addScanBreadcrumb(
      b.message as string || '',
      b.category as string,
      b.data as Record<string, unknown>,
    );
  },
  setMeasurement: (_name: string, _value: number, _unit: string) => {},
  flush: async (_timeout?: number): Promise<boolean> => {
    return flushSentry(_timeout);
  },
  startSpan: async (
    _opts: Record<string, unknown>,
    fn: () => Promise<unknown>,
  ) => fn(),
  init: (_opts: Record<string, unknown>) => {},
};

// --- Exported functions ---

export function initSentry(): void {
  const dsn = Deno.env.get('SENTRY_DSN');
  if (!dsn) {
    isEnabled = false;
    return;
  }

  const parsed = parseDsn(dsn);
  if (!parsed) {
    console.warn('Sentry: invalid DSN, running in disabled mode');
    isEnabled = false;
    return;
  }

  parsedDsn = parsed;
  isEnabled = true;

  // Reset state for new request
  breadcrumbBuffer.length = 0;
  pendingFetches.length = 0;
  scopeData.tags = {};
  scopeData.contexts = {};
  scopeData.extra = {};
  scopeData.user = null;
  scopeData.level = null;
  scopeData.fingerprint = null;

  scopeData.tags['service'] = 'security-scanner';
  scopeData.tags['runtime'] = 'deno';
}

export function startScanTransaction(
  _scanId: string,
  _projectRef: string,
): Span | null {
  return null;
}

export function startCheckSpan(
  _transaction: unknown,
  _checkId: string,
  _checkName: string,
): Span | null {
  return null;
}

export function setScanContext(context: Record<string, unknown>): void {
  if (!isEnabled) return;
  scopeData.contexts['scan'] = sanitizeValue(context) as Record<
    string,
    unknown
  >;
}

export function recordVulnerability(
  checkId: string,
  checkName: string,
  severity: string,
  affectedObjects: Array<{ schema: string; name: string; type: string }>,
  scanId: string,
): void {
  if (!isEnabled) return;

  const message = `Vulnerability: ${checkName} (${severity})`;
  const extra = {
    check_id: checkId,
    severity,
    scan_id: scanId,
    affected_count: affectedObjects.length,
    affected_objects: affectedObjects.slice(0, 10).map((o) =>
      `${o.schema}.${o.name} (${o.type})`
    ),
  };

  const envelope = buildMessageEnvelope(message, 'warning', extra);
  sendEnvelope(envelope);
}

export function recordScanMetrics(
  scanId: string,
  metrics: Record<string, number>,
): void {
  if (!isEnabled) return;
  addScanBreadcrumb('Scan metrics', 'metrics', {
    scan_id: scanId,
    ...metrics,
  });
}

export function addScanBreadcrumb(
  message: string,
  category?: string,
  data?: Record<string, unknown>,
): void {
  const breadcrumb: BreadcrumbEntry = {
    type: 'default',
    category: category || 'scanner',
    message: sanitizeString(message),
    level: 'info',
    timestamp: Date.now() / 1000,
  };

  if (data) {
    breadcrumb.data = truncateData(
      sanitizeValue(data) as Record<string, unknown>,
    );
  }

  breadcrumbBuffer.push(breadcrumb);

  while (breadcrumbBuffer.length > MAX_BREADCRUMBS) {
    breadcrumbBuffer.shift();
  }
}

export function captureError(
  error: Error,
  context?: Record<string, unknown>,
): string {
  if (!isEnabled) return 'disabled';

  const envelope = buildErrorEnvelope(error, context);
  sendEnvelope(envelope);
  return generateEventId();
}

export function captureGitHubError(
  error: Error,
  operation: string,
  context?: Record<string, unknown>,
): void {
  if (!isEnabled) return;

  scopeData.tags['github_operation'] = operation;
  const envelope = buildErrorEnvelope(error, {
    ...context,
    github_operation: operation,
  });
  sendEnvelope(envelope);
}

export async function flushSentry(timeout?: number): Promise<boolean> {
  if (!isEnabled || pendingFetches.length === 0) return true;

  const maxWait = timeout || 2000;

  try {
    await Promise.race([
      Promise.allSettled(pendingFetches),
      new Promise((resolve) => setTimeout(resolve, maxWait)),
    ]);
  } catch {
    // Flush failures should never block the response
  }

  pendingFetches.length = 0;
  return true;
}

export function withSentry<T>(
  fn: () => Promise<T>,
  _operationName: string,
): Promise<T> {
  return fn();
}

export function wrapHandler(
  handler: (req: Request) => Promise<Response>,
): (req: Request) => Promise<Response> {
  return handler;
}
