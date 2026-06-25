const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function defaultExtensionDir() {
  return path.resolve(__dirname, '..');
}

function defaultProjectRoot(extensionDir) {
  return path.resolve(extensionDir, '..', '..');
}

function bundleElixirServer(options = {}) {
  const extensionDir = options.extensionDir || defaultExtensionDir();
  const projectRoot = options.projectRoot || defaultProjectRoot(extensionDir);
  const runCommand = options.runCommand || spawnSync;
  const serverAppDir = path.join(projectRoot, 'server', 'apps', 'phoenix_ls');
  const source = path.join(serverAppDir, 'phoenix_ls');
  const target = path.join(extensionDir, 'server', 'phoenix_ls');

  const result = runCommand('mix', ['escript.build'], {
    cwd: serverAppDir,
    encoding: 'utf8',
    stdio: 'pipe',
    env: { ...process.env, MIX_ENV: 'prod' }
  });

  if (result.error) {
    throw new Error(`mix escript.build failed: ${result.error.message}`);
  }

  if (result.status !== 0) {
    const message = String(result.stderr || result.stdout || `exit ${result.status}`).trim();
    throw new Error(`mix escript.build failed: ${message}`);
  }

  if (!fs.existsSync(source)) {
    throw new Error(`mix escript.build did not produce ${source}`);
  }

  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
  fs.chmodSync(target, 0o755);

  return { source, target };
}

if (require.main === module) {
  try {
    const result = bundleElixirServer();
    console.log(`Bundled Phoenix LS executable: ${result.target}`);
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

module.exports = { bundleElixirServer };
