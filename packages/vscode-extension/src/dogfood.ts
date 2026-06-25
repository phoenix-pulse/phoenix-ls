import fs from 'fs';
import path from 'path';

const dogfoodMethods = [
  'phoenix/listSchemas',
  'phoenix/listComponents',
  'phoenix/listRoutes',
  'phoenix/listTemplates',
  'phoenix/listEvents',
  'phoenix/listLiveView',
  'phoenix/listUploads',
  'phoenix/listHooks',
  'phoenix/listColocatedAssets',
  'phoenix/listControllers'
];

interface DogfoodClient {
  sendRequest(method: string, params: Record<string, never>): Promise<unknown>;
}

interface OutputChannel {
  appendLine(message: string): void;
}

export async function maybeWriteDogfoodSnapshot(
  client: DogfoodClient,
  outputChannel?: OutputChannel
): Promise<Record<string, unknown> | null> {
  const snapshotPath = process.env.PHOENIX_PULSE_DOGFOOD_SNAPSHOT;
  if (!snapshotPath) return null;

  const results: Record<string, unknown> = {};

  for (const method of dogfoodMethods) {
    results[method] = await client.sendRequest(method, {});
  }

  const snapshot = {
    counts: Object.fromEntries(
      Object.entries(results).map(([method, result]) => [
        method,
        Array.isArray(result) ? result.length : null
      ])
    ),
    results
  };

  fs.mkdirSync(path.dirname(snapshotPath), { recursive: true });
  fs.writeFileSync(snapshotPath, JSON.stringify(snapshot, null, 2));
  outputChannel?.appendLine(`[Phoenix Pulse] Dogfood custom request snapshot written: ${snapshotPath}`);

  return snapshot;
}
