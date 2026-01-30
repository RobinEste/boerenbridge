/**
 * Sentry Integration Stub for Security Scanner
 *
 * No-op implementation that provides the same API surface.
 * When Sentry is needed, replace this file with the real implementation
 * and update the import to use the actual Sentry SDK.
 */

// Stub span/transaction objects
const noopSpan = {
  setStatus: (_s: string) => {},
  setData: (_k: string, _v: unknown) => {},
  setHttpStatus: (_c: number) => {},
  finish: () => {},
  startChild: (_opts: Record<string, unknown>) => noopSpan,
};

// Stub Sentry namespace
export const Sentry = {
  startTransaction: (_opts: Record<string, unknown>) => noopSpan,
  getCurrentHub: () => ({
    configureScope: (fn: (scope: unknown) => void) => {},
  }),
  configureScope: (_fn: (scope: unknown) => void) => {},
  withScope: (fn: (scope: Record<string, unknown>) => void) => {
    fn({
      setLevel: () => {},
      setContext: () => {},
      setTag: () => {},
      setFingerprint: () => {},
    });
  },
  captureMessage: (_msg: string, _level?: string) => {},
  captureException: (_err: unknown, _opts?: unknown) => 'stub-event-id',
  addBreadcrumb: (_b: Record<string, unknown>) => {},
  setMeasurement: (_name: string, _value: number, _unit: string) => {},
  flush: async (_timeout?: number) => true,
  startSpan: async (_opts: Record<string, unknown>, fn: () => Promise<unknown>) => fn(),
  init: (_opts: Record<string, unknown>) => {},
};

export function initSentry(): void {
  // No-op: Sentry not configured
}

export function startScanTransaction(
  _scanId: string,
  _projectRef: string
): typeof noopSpan | null {
  return null;
}

export function startCheckSpan(
  _transaction: unknown,
  _checkId: string,
  _checkName: string
): typeof noopSpan | null {
  return null;
}

export function setScanContext(_context: Record<string, unknown>): void {}

export function recordVulnerability(
  _checkId: string,
  _checkName: string,
  _severity: string,
  _affectedObjects: Array<{ schema: string; name: string; type: string }>,
  _scanId: string
): void {}

export function recordScanMetrics(
  _scanId: string,
  _metrics: Record<string, number>
): void {}

export function addScanBreadcrumb(
  _message: string,
  _category?: string,
  _data?: Record<string, unknown>
): void {}

export function captureError(
  _error: Error,
  _context?: Record<string, unknown>
): string {
  return 'stub-event-id';
}

export function captureGitHubError(
  _error: Error,
  _operation: string,
  _context?: Record<string, unknown>
): void {}

export async function flushSentry(_timeout?: number): Promise<boolean> {
  return true;
}

export function withSentry<T>(
  fn: () => Promise<T>,
  _operationName: string
): Promise<T> {
  return fn();
}

export function wrapHandler(
  handler: (req: Request) => Promise<Response>
): (req: Request) => Promise<Response> {
  return handler;
}
