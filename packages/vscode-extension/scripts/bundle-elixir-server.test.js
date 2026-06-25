import fs from 'fs';
import os from 'os';
import path from 'path';
import { createRequire } from 'module';
import { describe, expect, test } from 'vitest';

const require = createRequire(import.meta.url);
const { bundleElixirServer } = require('./bundle-elixir-server');

describe('bundleElixirServer', () => {
  test('builds the escript and copies it into the VS Code extension server directory', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-vscode-bundle-'));
    const extensionDir = path.join(root, 'packages', 'vscode-extension');
    const serverAppDir = path.join(root, 'server', 'apps', 'phoenix_ls');

    fs.mkdirSync(extensionDir, { recursive: true });
    fs.mkdirSync(serverAppDir, { recursive: true });

    const calls = [];

    const result = bundleElixirServer({
      extensionDir,
      projectRoot: root,
      runCommand(command, args, options) {
        calls.push({ command, args, cwd: options.cwd, env: options.env });
        fs.writeFileSync(path.join(serverAppDir, 'phoenix_ls'), '#!/usr/bin/env escript\n');
        return { status: 0, stderr: '', stdout: 'generated\n' };
      }
    });

    const bundledPath = path.join(extensionDir, 'server', 'phoenix_ls');

    expect(calls).toEqual([
      {
        command: 'mix',
        args: ['escript.build'],
        cwd: serverAppDir,
        env: expect.objectContaining({ MIX_ENV: 'prod' })
      }
    ]);
    expect(result).toEqual({ source: path.join(serverAppDir, 'phoenix_ls'), target: bundledPath });
    expect(fs.readFileSync(bundledPath, 'utf8')).toBe('#!/usr/bin/env escript\n');
    expect(fs.statSync(bundledPath).mode & 0o111).not.toBe(0);
  });

  test('fails when mix cannot build the escript', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-vscode-bundle-'));
    const extensionDir = path.join(root, 'packages', 'vscode-extension');

    fs.mkdirSync(extensionDir, { recursive: true });

    expect(() =>
      bundleElixirServer({
        extensionDir,
        projectRoot: root,
        runCommand() {
          return { status: 1, stderr: 'boom', stdout: '' };
        }
      })
    ).toThrow('mix escript.build failed: boom');
  });
});
