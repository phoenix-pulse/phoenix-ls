import fs from 'fs';
import os from 'os';
import path from 'path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const vscodeState = vi.hoisted(() => ({
  config: {
    serverPath: '',
    sourceOnlyMode: true,
    logLevel: 'info',
    indexingEnabled: true
  }
}));

vi.mock('vscode', () => ({
  workspace: {
    getConfiguration: vi.fn(() => ({
      get: vi.fn((key: string, defaultValue?: unknown) => {
        if (key === 'serverPath') return vscodeState.config.serverPath;
        if (key === 'sourceOnlyMode') return vscodeState.config.sourceOnlyMode;
        if (key === 'logLevel') return vscodeState.config.logLevel;
        if (key === 'indexing.enabled') return vscodeState.config.indexingEnabled;
        return defaultValue;
      })
    }))
  }
}));

import { resolveServer } from './server-resolver';

describe('resolveServer', () => {
  let root: string;
  let oldServerPath: string | undefined;

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-resolver-'));
    oldServerPath = process.env.PHOENIX_LS_SERVER_PATH;
    delete process.env.PHOENIX_LS_SERVER_PATH;
    vscodeState.config = {
      serverPath: '',
      sourceOnlyMode: true,
      logLevel: 'info',
      indexingEnabled: true
    };
  });

  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true });

    if (oldServerPath === undefined) {
      delete process.env.PHOENIX_LS_SERVER_PATH;
    } else {
      process.env.PHOENIX_LS_SERVER_PATH = oldServerPath;
    }
  });

  it('does not resolve a bundled server file that is not executable', () => {
    const bundledServer = path.join(root, 'server', 'phoenix_ls');
    fs.mkdirSync(path.dirname(bundledServer), { recursive: true });
    fs.writeFileSync(bundledServer, '#!/bin/sh\n');
    fs.chmodSync(bundledServer, 0o644);

    const outputChannel = { appendLine: vi.fn() };
    const context = {
      asAbsolutePath(relativePath: string) {
        return path.join(root, relativePath);
      }
    };

    expect(resolveServer(context as never, outputChannel as never)).toBeUndefined();
    expect(outputChannel.appendLine).toHaveBeenCalledWith(
      expect.stringContaining('not executable')
    );
  });
});
