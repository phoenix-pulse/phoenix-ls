const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const extensionId = 'onsever.phoenix-pulse';

function defaultExtensionDir() {
  return path.resolve(__dirname, '..');
}

function defaultProjectRoot(extensionDir) {
  return path.resolve(extensionDir, '..', '..');
}

function defaultFixtureRoot(projectRoot) {
  return path.join(
    projectRoot,
    'server',
    'apps',
    'phoenix_ls',
    'test',
    'fixtures',
    'liveview_components_app'
  );
}

async function dogfoodVSCode(options = {}) {
  const extensionDir = options.extensionDir || defaultExtensionDir();
  const projectRoot = options.projectRoot || defaultProjectRoot(extensionDir);
  const fixtureRoot = options.fixtureRoot || defaultFixtureRoot(projectRoot);
  const runCommand = options.runCommand || spawnSync;
  const codeCommand = options.codeCommand || 'code';
  const dogfoodRoot = options.dogfoodRoot || defaultDogfoodRoot();
  const timeoutMs = options.timeoutMs || 20_000;
  const pollIntervalMs = options.pollIntervalMs || 250;
  const openEditor = options.openEditor || defaultOpenEditor(codeCommand, runCommand, extensionDir);
  const killIsolatedEditor = options.killIsolatedEditor || defaultKillIsolatedEditor;

  const workspaceRoot = path.join(dogfoodRoot, path.basename(fixtureRoot));
  const userDataDir = path.join(dogfoodRoot, 'code-user');
  const extensionsDir = path.join(dogfoodRoot, 'code-extensions');

  fs.accessSync(fixtureRoot, fs.constants.R_OK);
  fs.rmSync(workspaceRoot, { recursive: true, force: true });
  fs.cpSync(fixtureRoot, workspaceRoot, { recursive: true });
  fs.mkdirSync(userDataDir, { recursive: true });
  fs.mkdirSync(extensionsDir, { recursive: true });

  try {
    runChecked(runCommand, 'npm', ['run', 'package'], { cwd: extensionDir });

    const vsixPath = latestVsix(extensionDir);

    runChecked(
      runCommand,
      codeCommand,
      [
        '--user-data-dir',
        userDataDir,
        '--extensions-dir',
        extensionsDir,
        '--install-extension',
        vsixPath,
        '--force'
      ],
      { cwd: extensionDir }
    );

    const extensionList = runChecked(
      runCommand,
      codeCommand,
      ['--user-data-dir', userDataDir, '--extensions-dir', extensionsDir, '--list-extensions', '--show-versions'],
      { cwd: extensionDir }
    ).stdout;

    const installedExtension = extensionList
      .split(/\r?\n/)
      .find(line => line.trim().toLowerCase().startsWith(`${extensionId}@`));

    if (!installedExtension) {
      throw new Error(`VS Code dogfood did not install ${extensionId}`);
    }

    openEditor({ dogfoodRoot, userDataDir, extensionsDir, workspaceRoot });

    const observed = await waitForLogChecks(dogfoodRoot, timeoutMs, pollIntervalMs);

    const status = runChecked(
      runCommand,
      codeCommand,
      ['--user-data-dir', userDataDir, '--extensions-dir', extensionsDir, '--status'],
      { cwd: extensionDir }
    ).stdout;

    const bundledProcess = /server[\/\\]phoenix_ls[\s\S]*--stdio/.test(status);
    const logChecks = { ...observed.checks, bundledProcess };
    const missing = missingChecks(logChecks);

    if (logChecks.noPhoenixErrors === false) {
      throw new Error('VS Code dogfood observed Phoenix Pulse log errors');
    }

    if (missing.length > 0) {
      throw new Error(`VS Code dogfood did not observe: ${missing.join(', ')}`);
    }

    return {
      dogfoodRoot,
      workspaceRoot,
      userDataDir,
      extensionsDir,
      vsixPath,
      extensionId: installedExtension.trim(),
      phoenixLog: observed.phoenixLog,
      logChecks
    };
  } finally {
    killIsolatedEditor(userDataDir);
  }
}

function defaultDogfoodRoot() {
  const tmpParent = process.platform === 'darwin' && fs.existsSync('/tmp') ? '/tmp' : os.tmpdir();
  return fs.mkdtempSync(path.join(tmpParent, 'phoenix-pulse-vscode-dogfood.'));
}

function runChecked(runCommand, command, args, options) {
  const result = runCommand(command, args, { encoding: 'utf8', stdio: 'pipe', ...options });

  if (result.error) {
    throw new Error(`${command} ${args.join(' ')} failed: ${result.error.message}`);
  }

  if (result.status !== 0) {
    const output = String(result.stderr || result.stdout || `exit ${result.status}`).trim();
    throw new Error(`${command} ${args.join(' ')} failed: ${output}`);
  }

  return { stdout: String(result.stdout || ''), stderr: String(result.stderr || '') };
}

function latestVsix(extensionDir) {
  const candidates = fs
    .readdirSync(extensionDir)
    .filter(name => name.endsWith('.vsix'))
    .map(name => path.join(extensionDir, name))
    .sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);

  if (candidates.length === 0) {
    throw new Error(`VS Code package did not produce a VSIX in ${extensionDir}`);
  }

  return candidates[0];
}

function defaultOpenEditor(codeCommand, runCommand, extensionDir) {
  return ({ userDataDir, extensionsDir, workspaceRoot }) => {
    runChecked(
      runCommand,
      codeCommand,
      [
        '--user-data-dir',
        userDataDir,
        '--extensions-dir',
        extensionsDir,
        '--new-window',
        '--log',
        'trace',
        workspaceRoot
      ],
      { cwd: extensionDir }
    );
  };
}

function defaultKillIsolatedEditor(userDataDir) {
  if (process.platform === 'win32') return;

  terminateMatchingProcesses(userDataDir, 'SIGTERM');

  if (!waitForNoMatchingProcesses(userDataDir, 2_000)) {
    terminateMatchingProcesses(userDataDir, 'SIGKILL');
    waitForNoMatchingProcesses(userDataDir, 1_000);
  }
}

function terminateMatchingProcesses(userDataDir, signal) {
  for (const pid of matchingProcessIds(userDataDir)) {
    try {
      process.kill(pid, signal);
    } catch {
      // The process may exit between listing and signalling.
    }
  }
}

function waitForNoMatchingProcesses(userDataDir, timeoutMs) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() <= deadline) {
    if (matchingProcessIds(userDataDir).length === 0) {
      return true;
    }

    sleepSync(50);
  }

  return matchingProcessIds(userDataDir).length === 0;
}

function matchingProcessIds(userDataDir) {
  const result = spawnSync('ps', ['-axo', 'pid=,command='], { encoding: 'utf8', stdio: 'pipe' });

  if (result.status !== 0 || result.error) {
    return [];
  }

  return String(result.stdout || '')
    .split(/\r?\n/)
    .map(line => line.match(/^\s*(\d+)\s+(.+)$/))
    .filter(Boolean)
    .map(match => ({ pid: Number(match[1]), command: match[2] }))
    .filter(processInfo => processInfo.pid !== process.pid && processInfo.command.includes(userDataDir))
    .map(processInfo => processInfo.pid);
}

function sleepSync(ms) {
  const lock = new Int32Array(new SharedArrayBuffer(4));
  Atomics.wait(lock, 0, 0, ms);
}

async function waitForLogChecks(root, timeoutMs, pollIntervalMs) {
  const deadline = Date.now() + timeoutMs;
  let lastObserved = { checks: emptyChecks(), phoenixLog: null };

  while (Date.now() <= deadline) {
    lastObserved = readLogChecks(root);

    if (lastObserved.checks.noPhoenixErrors === false) {
      return lastObserved;
    }

    if (Object.values(lastObserved.checks).every(Boolean)) {
      return lastObserved;
    }

    await sleep(pollIntervalMs);
  }

  const missing = missingChecks(lastObserved.checks);
  throw new Error(`VS Code dogfood did not observe: ${missing.join(', ')}`);
}

function readLogChecks(root) {
  const phoenixLog = latestMatchingFile(path.join(root, 'code-user', 'logs'), /Phoenix Pulse\.log$/);
  const text = phoenixLog ? fs.readFileSync(phoenixLog, 'utf8') : '';

  return {
    phoenixLog,
    checks: {
      activation: text.includes('Phoenix Pulse extension activating...'),
      serverPath: /server[\/\\]phoenix_ls/.test(text),
      lspStarted: text.includes('Phoenix Pulse LSP client started successfully!'),
      explorerRegistered: text.includes('Phoenix Pulse Explorer registered successfully!'),
      noPhoenixErrors: !/\b(error|failed|unhandled)\b/i.test(text)
    }
  };
}

function latestMatchingFile(root, pattern) {
  if (!fs.existsSync(root)) return null;

  const matches = [];
  const stack = [root];

  while (stack.length > 0) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });

    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);

      if (entry.isDirectory()) {
        stack.push(fullPath);
      } else if (pattern.test(fullPath)) {
        matches.push(fullPath);
      }
    }
  }

  matches.sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);
  return matches[0] || null;
}

function emptyChecks() {
  return {
    activation: false,
    serverPath: false,
    lspStarted: false,
    explorerRegistered: false,
    noPhoenixErrors: true
  };
}

function missingChecks(checks) {
  return Object.entries(checks)
    .filter(([name, ok]) => name !== 'noPhoenixErrors' && !ok)
    .map(([name]) => name);
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function parseArgs(argv) {
  const args = {};

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--fixture') args.fixtureRoot = path.resolve(argv[++index]);
    else if (arg === '--code') args.codeCommand = argv[++index];
    else if (arg === '--timeout') args.timeoutMs = Number(argv[++index]);
    else if (arg === '--help') args.help = true;
    else throw new Error(`unknown argument: ${arg}`);
  }

  return args;
}

function usage() {
  return `Usage: node scripts/dogfood-vscode.js [--fixture PATH] [--code COMMAND] [--timeout MS]

Packages Phoenix Pulse, installs the VSIX into an isolated VS Code profile,
opens a Phoenix fixture workspace, and validates extension activation logs.
`;
}

if (require.main === module) {
  let args;

  try {
    args = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    console.error(usage());
    process.exit(1);
  }

  if (args.help) {
    process.stdout.write(usage());
  } else {
    dogfoodVSCode(args)
      .then(summary => {
        console.log(JSON.stringify(summary, null, 2));
      })
      .catch(error => {
        console.error(error.stack || error.message);
        process.exit(1);
      });
  }
}

module.exports = { dogfoodVSCode, defaultKillIsolatedEditor };
