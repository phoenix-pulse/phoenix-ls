import fs from 'fs';
import os from 'os';
import path from 'path';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { maybeWriteDogfoodSnapshot } from './dogfood';

describe('maybeWriteDogfoodSnapshot', () => {
  const originalSnapshotPath = process.env.PHOENIX_PULSE_DOGFOOD_SNAPSHOT;

  afterEach(() => {
    if (originalSnapshotPath === undefined) {
      delete process.env.PHOENIX_PULSE_DOGFOOD_SNAPSHOT;
    } else {
      process.env.PHOENIX_PULSE_DOGFOOD_SNAPSHOT = originalSnapshotPath;
    }
  });

  test('does nothing when dogfood snapshot path is not configured', async () => {
    delete process.env.PHOENIX_PULSE_DOGFOOD_SNAPSHOT;
    const client = { sendRequest: vi.fn() };

    await expect(maybeWriteDogfoodSnapshot(client)).resolves.toBeNull();

    expect(client.sendRequest).not.toHaveBeenCalled();
  });

  test('writes custom request responses and counts to configured snapshot path', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-pulse-dogfood-snapshot-'));
    const snapshotPath = path.join(root, 'nested', 'snapshot.json');
    process.env.PHOENIX_PULSE_DOGFOOD_SNAPSHOT = snapshotPath;

    const client = {
      sendRequest: vi.fn(async method => [{ method }])
    };

    const snapshot = await maybeWriteDogfoodSnapshot(client);
    const fileSnapshot = JSON.parse(fs.readFileSync(snapshotPath, 'utf8'));

    expect(client.sendRequest).toHaveBeenCalledWith('phoenix/listRoutes', {});
    expect(client.sendRequest).toHaveBeenCalledWith('phoenix/listTemplates', {});
    expect(client.sendRequest).toHaveBeenCalledWith('phoenix/listEvents', {});
    expect(client.sendRequest).toHaveBeenCalledWith('phoenix/listSchemas', {});
    expect(client.sendRequest).toHaveBeenCalledWith('phoenix/listComponents', {});
    expect(client.sendRequest).toHaveBeenCalledWith('phoenix/listLiveView', {});
    expect(client.sendRequest).toHaveBeenCalledWith('phoenix/listUploads', {});
    expect(client.sendRequest).toHaveBeenCalledWith('phoenix/listHooks', {});
    expect(client.sendRequest).toHaveBeenCalledWith('phoenix/listColocatedAssets', {});
    expect(client.sendRequest).toHaveBeenCalledWith('phoenix/listControllers', {});
    expect(snapshot).toEqual(fileSnapshot);
    expect(fileSnapshot.counts).toEqual({
      'phoenix/listSchemas': 1,
      'phoenix/listComponents': 1,
      'phoenix/listRoutes': 1,
      'phoenix/listTemplates': 1,
      'phoenix/listEvents': 1,
      'phoenix/listLiveView': 1,
      'phoenix/listUploads': 1,
      'phoenix/listHooks': 1,
      'phoenix/listColocatedAssets': 1,
      'phoenix/listControllers': 1
    });
    expect(fileSnapshot.results['phoenix/listRoutes'][0]).toEqual({
      method: 'phoenix/listRoutes'
    });
  });
});
