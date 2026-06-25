const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { spawn: spawnProcess } = require('child_process');

const defaultMethods = [
  'phoenix/listSchemas',
  'phoenix/listComponents',
  'phoenix/listRoutes',
  'phoenix/listTemplates',
  'phoenix/listEvents',
  'phoenix/listLiveView'
];

function defaultExtensionDir() {
  return path.resolve(__dirname, '..');
}

function defaultProjectRoot(extensionDir) {
  return path.resolve(extensionDir, '..', '..');
}

function defaultRootDir(projectRoot) {
  return path.join(projectRoot, 'server', 'apps', 'phoenix_ls', 'test', 'fixtures', 'liveview_components_app');
}

function defaultServerPath(extensionDir) {
  return path.join(extensionDir, 'server', 'phoenix_ls');
}

async function dogfoodBundledServer(options = {}) {
  const extensionDir = options.extensionDir || defaultExtensionDir();
  const projectRoot = options.projectRoot || defaultProjectRoot(extensionDir);
  const rootDir = options.rootDir || defaultRootDir(projectRoot);
  const serverPath = options.serverPath || defaultServerPath(extensionDir);
  const spawn = options.spawn || spawnProcess;
  const timeoutMs = options.timeoutMs || 10_000;
  const methods = options.methods || defaultMethods;
  const requiredMethods = options.requiredMethods || methods;

  fs.accessSync(rootDir, fs.constants.R_OK);
  fs.accessSync(serverPath, fs.constants.X_OK);

  const child = spawn(serverPath, ['--stdio'], {
    cwd: rootDir,
    env: {
      ...process.env,
      PHOENIX_LS_LOG_LEVEL: 'error',
      PHOENIX_LS_SOURCE_ONLY: '1',
      PHOENIX_LS_INDEXING: '1',
      PHOENIX_LS_COMPILATION: '0'
    },
    stdio: ['pipe', 'pipe', 'pipe']
  });

  const client = createJsonRpcClient(child, timeoutMs);
  const rootUri = pathToFileURL(rootDir).href;

  try {
    const initializeResult = await client.request('initialize', {
      processId: process.pid,
      rootUri,
      capabilities: {},
      workspaceFolders: [{ uri: rootUri, name: path.basename(rootDir) }]
    });

    client.notify('initialized', {});

    const results = {};
    for (const method of methods) {
      results[method] = await client.request(method, {});
    }

    await client.request('shutdown', null);
    client.notify('exit', null);
    child.stdin.end();

    const counts = Object.fromEntries(
      Object.entries(results).map(([method, result]) => [
        method,
        Array.isArray(result) ? result.length : null
      ])
    );
    const missing = requiredMethods.filter(
      method => !(Array.isArray(results[method]) && results[method].length > 0)
    );

    const summary = {
      rootDir,
      serverPath,
      serverInfo: initializeResult.serverInfo || initializeResult.server_info || null,
      counts,
      samples: Object.fromEntries(
        Object.entries(results).map(([method, result]) => [
          method,
          Array.isArray(result) ? result[0] || null : result
        ])
      ),
      notificationMethods: client.notifications.map(notification => notification.method).filter(Boolean),
      stderr: client.stderr().trim()
    };

    if (missing.length > 0) {
      throw new Error(`missing non-empty dogfood results for ${missing.join(', ')}`);
    }

    validateExplorerContracts(results);

    return summary;
  } catch (error) {
    child.kill('SIGTERM');
    throw error;
  }
}

function validateExplorerContracts(results) {
  validateRoutePayloads(results['phoenix/listRoutes'] || []);
  validateTemplatePayloads(results['phoenix/listTemplates'] || []);
  validateEventPayloads(results['phoenix/listEvents'] || []);
}

function validateRoutePayloads(routes) {
  routes.forEach((route, index) => {
    const missing = [];

    if (!nonEmptyString(route.verb)) missing.push('verb');
    if (!nonEmptyString(route.path)) missing.push('path');
    if (!nonEmptyString(route.filePath)) missing.push('filePath');
    if (!validLocation(route.location)) missing.push('location');
    if (!nonEmptyString(route.helperBase)) missing.push('helperBase');
    if (!nonEmptyString(route.helperName)) missing.push('helperName');
    if (!Array.isArray(route.helperVariants)) missing.push('helperVariants');
    if (!Array.isArray(route.pathParams)) missing.push('pathParams');
    if (!Array.isArray(route.pipelines)) missing.push('pipelines');

    if (missing.length > 0) {
      throw new Error(`phoenix/listRoutes[${index}] missing contract fields: ${missing.join(', ')}`);
    }
  });
}

function validateTemplatePayloads(templates) {
  templates.forEach((template, index) => {
    const missing = [];

    if (!nonEmptyString(template.name)) missing.push('name');
    if (!nonEmptyString(template.format)) missing.push('format');
    if (!nonEmptyString(template.kind)) missing.push('kind');
    if (!nonEmptyString(template.module)) missing.push('module');
    if (!nonEmptyString(template.filePath)) missing.push('filePath');
    if (!validLocation(template.location)) missing.push('location');

    if (missing.length > 0) {
      throw new Error(`phoenix/listTemplates[${index}] missing contract fields: ${missing.join(', ')}`);
    }
  });
}

function validateEventPayloads(events) {
  events.forEach((event, index) => {
    const missing = [];

    if (!nonEmptyString(event.name)) missing.push('name');
    if (!nonEmptyString(event.type)) missing.push('type');
    if (!nonEmptyString(event.handler)) missing.push('handler');
    if (typeof event.arity !== 'number' || !Number.isFinite(event.arity)) missing.push('arity');
    if (!nonEmptyString(event.module)) missing.push('module');
    if (!nonEmptyString(event.filePath)) missing.push('filePath');
    if (!validLocation(event.location)) missing.push('location');

    if (missing.length > 0) {
      throw new Error(`phoenix/listEvents[${index}] missing contract fields: ${missing.join(', ')}`);
    }
  });
}

function nonEmptyString(value) {
  return typeof value === 'string' && value.length > 0;
}

function validLocation(location) {
  return (
    location &&
    typeof location.line === 'number' &&
    Number.isFinite(location.line) &&
    typeof location.character === 'number' &&
    Number.isFinite(location.character)
  );
}

function createJsonRpcClient(child, timeoutMs) {
  let nextId = 1;
  let buffer = Buffer.alloc(0);
  const pending = new Map();
  const notifications = [];
  const stderrChunks = [];

  child.stdout.on('data', chunk => {
    buffer = Buffer.concat([buffer, Buffer.from(chunk)]);
    parseFrames();
  });

  child.stderr.on('data', chunk => {
    stderrChunks.push(Buffer.from(chunk).toString('utf8'));
  });

  child.on('exit', (code, signal) => {
    if (pending.size === 0) return;

    const reason = signal ? `server exited from ${signal}` : `server exited with ${code}`;
    for (const waiter of pending.values()) {
      clearTimeout(waiter.timer);
      waiter.reject(new Error(reason));
    }
    pending.clear();
  });

  function request(method, params) {
    const id = nextId++;

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`timeout waiting for ${method}`));
      }, timeoutMs);

      pending.set(id, {
        method,
        timer,
        resolve: value => {
          clearTimeout(timer);
          resolve(value);
        },
        reject: error => {
          clearTimeout(timer);
          reject(error);
        }
      });

      send({ jsonrpc: '2.0', id, method, params });
    });
  }

  function notify(method, params) {
    send({ jsonrpc: '2.0', method, params });
  }

  function send(message) {
    const body = Buffer.from(JSON.stringify(message), 'utf8');
    child.stdin.write(
      Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, 'utf8'), body])
    );
  }

  function parseFrames() {
    while (true) {
      const headerEnd = buffer.indexOf('\r\n\r\n');
      if (headerEnd === -1) return;

      const header = buffer.slice(0, headerEnd).toString('utf8');
      const length = contentLength(header);
      const bodyStart = headerEnd + 4;
      const bodyEnd = bodyStart + length;
      if (buffer.length < bodyEnd) return;

      const message = JSON.parse(buffer.slice(bodyStart, bodyEnd).toString('utf8'));
      buffer = buffer.slice(bodyEnd);
      handleMessage(message);
    }
  }

  function handleMessage(message) {
    if (Object.prototype.hasOwnProperty.call(message, 'id') && pending.has(message.id)) {
      const waiter = pending.get(message.id);
      pending.delete(message.id);

      if (message.error) {
        waiter.reject(new Error(`${waiter.method}: ${JSON.stringify(message.error)}`));
      } else {
        waiter.resolve(message.result);
      }
    } else {
      notifications.push(message);
    }
  }

  return {
    request,
    notify,
    notifications,
    stderr: () => stderrChunks.join('')
  };
}

function contentLength(header) {
  for (const line of header.split('\r\n')) {
    const [name, value] = line.split(':', 2);
    if (name.toLowerCase() === 'content-length') return Number(value.trim());
  }

  throw new Error(`missing Content-Length in ${JSON.stringify(header)}`);
}

function parseArgs(argv) {
  const args = {};

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--root') args.rootDir = path.resolve(argv[++index]);
    else if (arg === '--server') args.serverPath = path.resolve(argv[++index]);
    else if (arg === '--timeout') args.timeoutMs = Number(argv[++index]);
    else if (arg === '--help') args.help = true;
    else throw new Error(`unknown argument: ${arg}`);
  }

  return args;
}

function usage() {
  return `Usage: node scripts/dogfood-bundled-server.js [--root PATH] [--server PATH] [--timeout MS]

Runs the bundled Phoenix LS executable over stdio against a Phoenix fixture and
asserts the explorer requests return real payloads.
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
    dogfoodBundledServer(args)
      .then(summary => {
        console.log(JSON.stringify(summary, null, 2));
      })
      .catch(error => {
        console.error(error.stack || error.message);
        process.exit(1);
      });
  }
}

module.exports = { dogfoodBundledServer, defaultMethods };
