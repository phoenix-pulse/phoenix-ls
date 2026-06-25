import fs from 'fs';
import os from 'os';
import path from 'path';
import { createRequire } from 'module';
import { spawn } from 'child_process';
import { describe, expect, test } from 'vitest';

const require = createRequire(import.meta.url);
const { dogfoodVSCode, defaultKillIsolatedEditor } = require('./dogfood-vscode');

describe('dogfoodVSCode', () => {
  test('installs a packaged VSIX into an isolated profile and validates Phoenix Pulse logs', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-vscode-dogfood-test-'));
    const extensionDir = path.join(root, 'packages', 'vscode-extension');
    const projectRoot = root;
    const fixtureRoot = path.join(root, 'fixture');
    const vsixPath = path.join(extensionDir, 'phoenix-pulse-1.3.0.vsix');
    const calls = [];
    const killed = [];

    fs.mkdirSync(extensionDir, { recursive: true });
    fs.mkdirSync(fixtureRoot, { recursive: true });
    fs.writeFileSync(path.join(fixtureRoot, 'mix.exs'), 'defmodule Fixture.MixProject do\nend\n');
    fs.writeFileSync(vsixPath, 'vsix');

    const summary = await dogfoodVSCode({
      extensionDir,
      projectRoot,
      fixtureRoot,
      codeCommand: process.execPath,
      timeoutMs: 200,
      pollIntervalMs: 1,
      runCommand(command, args, options) {
        calls.push({ command, args, cwd: options.cwd });

        if (command === 'npm' && args.join(' ') === 'run package') {
          return { status: 0, stdout: 'packaged', stderr: '' };
        }

        if (command === process.execPath && args.includes('--install-extension')) {
          return { status: 0, stdout: 'installed', stderr: '' };
        }

        if (command === process.execPath && args.includes('--list-extensions')) {
          return { status: 0, stdout: 'onsever.phoenix-pulse@1.3.0\n', stderr: '' };
        }

        if (command === process.execPath && args.includes('--new-window')) {
          writeVSCodeLogs(path.dirname(argValue(args, '--user-data-dir')));
          return { status: 0, stdout: 'opened', stderr: '' };
        }

        if (command === process.execPath && args.includes('--status')) {
          return {
            status: 0,
            stdout: '/tmp/code-extensions/onsever.phoenix-pulse-1.3.0/server/phoenix_ls --stdio\n',
            stderr: ''
          };
        }

        throw new Error(`unexpected command: ${command} ${args.join(' ')}`);
      },
      killIsolatedEditor(match) {
        killed.push(match);
      }
    });

    expect(summary.extensionId).toBe('onsever.phoenix-pulse@1.3.0');
    if (process.platform === 'darwin') {
      expect(summary.dogfoodRoot).toMatch(/^\/tmp\/phoenix-pulse-vscode-dogfood\./);
    }
    expect(summary.logChecks).toEqual({
      activation: true,
      serverPath: true,
      lspStarted: true,
      explorerRegistered: true,
      noPhoenixErrors: true,
      bundledProcess: true
    });
    expect(calls.map(call => call.command)).toEqual([
      'npm',
      process.execPath,
      process.execPath,
      process.execPath,
      process.execPath
    ]);
    expect(calls[1].args).toEqual(expect.arrayContaining(['--install-extension', vsixPath, '--force']));
    expect(calls[3].args).toEqual(
      expect.arrayContaining(['--new-window', '--log', 'trace', expect.stringContaining('fixture')])
    );
    expect(calls[3].args).toEqual(expect.arrayContaining(['--user-data-dir', expect.stringContaining('code-user')]));
    expect(calls[3].args).toEqual(expect.arrayContaining(['--extensions-dir', expect.stringContaining('code-extensions')]));
    expect(killed).toEqual([expect.stringContaining('code-user')]);
  });

  test('fails when VS Code window launch fails', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-vscode-dogfood-test-'));
    const extensionDir = path.join(root, 'packages', 'vscode-extension');
    const fixtureRoot = path.join(root, 'fixture');

    fs.mkdirSync(extensionDir, { recursive: true });
    fs.mkdirSync(fixtureRoot, { recursive: true });
    fs.writeFileSync(path.join(fixtureRoot, 'mix.exs'), 'defmodule Fixture.MixProject do\nend\n');
    fs.writeFileSync(path.join(extensionDir, 'phoenix-pulse-1.3.0.vsix'), 'vsix');

    await expect(
      dogfoodVSCode({
        extensionDir,
        projectRoot: root,
        fixtureRoot,
        codeCommand: process.execPath,
        timeoutMs: 20,
        pollIntervalMs: 1,
        runCommand(command, args) {
          if (command === 'npm') return { status: 0, stdout: '', stderr: '' };
          if (command === process.execPath && args.includes('--install-extension')) {
            return { status: 0, stdout: 'installed', stderr: '' };
          }
          if (command === process.execPath && args.includes('--list-extensions')) {
            return { status: 0, stdout: 'onsever.phoenix-pulse@1.3.0\n', stderr: '' };
          }
          if (command === process.execPath && args.includes('--new-window')) {
            return { status: 1, stdout: '', stderr: 'listen EINVAL: invalid argument socket path' };
          }

          return { status: 64, stdout: '', stderr: `unexpected ${command}` };
        },
        killIsolatedEditor() {}
      })
    ).rejects.toThrow('listen EINVAL: invalid argument socket path');
  });

  test('fails when activation logs are missing expected markers', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-vscode-dogfood-test-'));
    const extensionDir = path.join(root, 'packages', 'vscode-extension');
    const fixtureRoot = path.join(root, 'fixture');

    fs.mkdirSync(extensionDir, { recursive: true });
    fs.mkdirSync(fixtureRoot, { recursive: true });
    fs.writeFileSync(path.join(fixtureRoot, 'mix.exs'), 'defmodule Fixture.MixProject do\nend\n');
    fs.writeFileSync(path.join(extensionDir, 'phoenix-pulse-1.3.0.vsix'), 'vsix');

    await expect(
      dogfoodVSCode({
        extensionDir,
        projectRoot: root,
        fixtureRoot,
        timeoutMs: 20,
        pollIntervalMs: 1,
        runCommand(command, args) {
          if (command === 'npm') return { status: 0, stdout: '', stderr: '' };
          if (command === 'code' && args.includes('--install-extension')) {
            return { status: 0, stdout: 'installed', stderr: '' };
          }
          if (command === 'code' && args.includes('--list-extensions')) {
            return { status: 0, stdout: 'onsever.phoenix-pulse@1.3.0\n', stderr: '' };
          }
          if (command === 'code' && args.includes('--status')) {
            return { status: 0, stdout: '', stderr: '' };
          }

          return { status: 64, stdout: '', stderr: `unexpected ${command}` };
        },
        openEditor() {},
        killIsolatedEditor() {}
      })
    ).rejects.toThrow('VS Code dogfood did not observe: activation');
  });

  test('fails when Phoenix Pulse logs contain runtime errors', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-vscode-dogfood-test-'));
    const extensionDir = path.join(root, 'packages', 'vscode-extension');
    const fixtureRoot = path.join(root, 'fixture');

    fs.mkdirSync(extensionDir, { recursive: true });
    fs.mkdirSync(fixtureRoot, { recursive: true });
    fs.writeFileSync(path.join(fixtureRoot, 'mix.exs'), 'defmodule Fixture.MixProject do\nend\n');
    fs.writeFileSync(path.join(extensionDir, 'phoenix-pulse-1.3.0.vsix'), 'vsix');

    await expect(
      dogfoodVSCode({
        extensionDir,
        projectRoot: root,
        fixtureRoot,
        timeoutMs: 50,
        pollIntervalMs: 1,
        runCommand(command, args) {
          if (command === 'npm') return { status: 0, stdout: '', stderr: '' };
          if (command === 'code' && args.includes('--install-extension')) {
            return { status: 0, stdout: 'installed', stderr: '' };
          }
          if (command === 'code' && args.includes('--list-extensions')) {
            return { status: 0, stdout: 'onsever.phoenix-pulse@1.3.0\n', stderr: '' };
          }
          if (command === 'code' && args.includes('--status')) {
            return {
              status: 0,
              stdout: '/tmp/code-extensions/onsever.phoenix-pulse-1.3.0/server/phoenix_ls --stdio\n',
              stderr: ''
            };
          }

          return { status: 64, stdout: '', stderr: `unexpected ${command}` };
        },
        openEditor({ dogfoodRoot }) {
          writeVSCodeLogs(dogfoodRoot, ['[Phoenix Pulse] Failed to navigate to item: boom']);
        },
        killIsolatedEditor() {}
      })
    ).rejects.toThrow('VS Code dogfood observed Phoenix Pulse log errors');
  });

  test('default cleanup terminates processes using the isolated user data dir', async () => {
    if (process.platform === 'win32') return;

    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-vscode-cleanup-test-'));
    const userDataDir = path.join(root, 'code-user');
    const child = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)', userDataDir], {
      stdio: 'ignore'
    });

    try {
      await waitForProcess(child.pid);

      defaultKillIsolatedEditor(userDataDir);

      await waitForExit(child);
      expect(child.exitCode !== null || child.signalCode !== null).toBe(true);
    } finally {
      if (child.exitCode === null && child.signalCode === null && isProcessRunning(child.pid)) {
        process.kill(child.pid, 'SIGKILL');
      }
    }
  });
});

function writeVSCodeLogs(root, extraLines = []) {
  const logDir = path.join(root, 'code-user', 'logs', '20260625T120000', 'window1', 'exthost');
  const outputDir = path.join(logDir, 'output_logging_20260625T120001');

  fs.mkdirSync(outputDir, { recursive: true });
  fs.writeFileSync(
    path.join(outputDir, '1-Phoenix Pulse.log'),
    [
      'Phoenix Pulse extension activating...',
      'Starting Elixir language server; project detection runs in the server.',
      'Phoenix LS executable path: /tmp/code-extensions/onsever.phoenix-pulse-1.3.0/server/phoenix_ls',
      'Starting Phoenix Pulse LSP client...',
      'Phoenix Pulse LSP client started successfully!',
      'Phoenix Pulse Explorer registered successfully!',
      ...extraLines
    ].join('\n')
  );
}

function argValue(args, name) {
  const index = args.indexOf(name);
  if (index === -1) throw new Error(`missing argument ${name}`);
  return args[index + 1];
}

async function waitForProcess(pid) {
  const deadline = Date.now() + 1000;

  while (Date.now() <= deadline) {
    if (isProcessRunning(pid)) return;
    await new Promise(resolve => setTimeout(resolve, 10));
  }

  throw new Error(`process ${pid} did not start`);
}

function isProcessRunning(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function waitForExit(child) {
  if (child.exitCode !== null || child.signalCode !== null) return;

  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error(`process ${child.pid} did not exit`));
    }, 1000);

    child.once('exit', () => {
      clearTimeout(timeout);
      resolve();
    });
  });
}
