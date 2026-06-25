import fs from 'fs';
import os from 'os';
import path from 'path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const vscodeState = vi.hoisted(() => ({
  config: {
    serverPath: '',
    sourceOnlyMode: true,
    logLevel: 'info',
    indexingEnabled: true,
    compilationEnabled: false
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
        if (key === 'compilation.enabled') return vscodeState.config.compilationEnabled;
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
      indexingEnabled: true,
      compilationEnabled: false
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

  it('passes runtime settings to the Elixir executable environment', () => {
    const bundledServer = path.join(root, 'server', 'phoenix_ls');
    fs.mkdirSync(path.dirname(bundledServer), { recursive: true });
    fs.writeFileSync(bundledServer, '#!/bin/sh\n');
    fs.chmodSync(bundledServer, 0o755);

    vscodeState.config = {
      serverPath: '',
      sourceOnlyMode: false,
      logLevel: 'debug',
      indexingEnabled: false,
      compilationEnabled: true
    };

    const outputChannel = { appendLine: vi.fn() };
    const context = {
      asAbsolutePath(relativePath: string) {
        return path.join(root, relativePath);
      }
    };

    const resolved = resolveServer(context as never, outputChannel as never);

    expect(resolved?.command).toBe(bundledServer);
    expect(resolved?.args).toEqual(['--stdio']);
    expect(resolved?.env).toMatchObject({
      PHOENIX_LS_SOURCE_ONLY: '0',
      PHOENIX_LS_LOG_LEVEL: 'debug',
      PHOENIX_LS_INDEXING: '0',
      PHOENIX_LS_COMPILATION: '1'
    });
  });

  it('contributes a compilation setting for the Elixir server', () => {
    const packageJson = JSON.parse(
      fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8')
    );

    expect(packageJson.contributes.configuration.properties).toMatchObject({
      'phoenixPulse.compilation.enabled': {
        type: 'boolean',
        default: false
      }
    });
  });
});
