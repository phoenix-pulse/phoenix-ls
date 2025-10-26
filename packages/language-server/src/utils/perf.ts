import { performance } from 'perf_hooks';

const DEBUG_PERF = process.env.PHOENIX_LSP_DEBUG_PERF === 'true';

export class PerfTimer {
  private label: string;
  private start: number;
  private enabled: boolean;

  constructor(label: string) {
    this.label = label;
    this.enabled = DEBUG_PERF;
    this.start = this.enabled ? performance.now() : 0;
  }

  stop(additionalInfo?: Record<string, unknown>) {
    if (!this.enabled) {
      return;
    }

    const duration = performance.now() - this.start;
    const payload = additionalInfo ? ` ${JSON.stringify(additionalInfo)}` : '';
    console.log(`[Perf] ${this.label}: ${duration.toFixed(2)}ms${payload}`);
  }
}

export function time<T>(label: string, fn: () => T, context?: Record<string, unknown>): T {
  if (!DEBUG_PERF) {
    return fn();
  }

  const timer = new PerfTimer(label);
  try {
    return fn();
  } finally {
    timer.stop(context);
  }
}
