import { EventEmitter } from 'events';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { createRequire } from 'module';
import { describe, expect, test } from 'vitest';

const require = createRequire(import.meta.url);
const { dogfoodBundledServer, defaultMethods } = require('./dogfood-bundled-server');

describe('dogfoodBundledServer', () => {
  test('drives raw phoenix requests through a bundled stdio server', async () => {
    const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-dogfood-root-'));
    const serverPath = path.join(rootDir, 'phoenix_ls');
    fs.writeFileSync(serverPath, '#!/bin/sh\n');
    fs.chmodSync(serverPath, 0o755);

    const spawn = createFakeServerSpawn({ results: completeExplorerResults() });

    const summary = await dogfoodBundledServer({ rootDir, serverPath, spawn });

    expect(spawn.calls).toEqual([
      expect.objectContaining({
        command: serverPath,
        args: ['--stdio'],
        cwd: rootDir,
        env: expect.objectContaining({
          PHOENIX_LS_SOURCE_ONLY: '1',
          PHOENIX_LS_INDEXING: '1',
          PHOENIX_LS_COMPILATION: '0'
        })
      })
    ]);
    expect(spawn.requests.map(request => request.method)).toEqual([
      'initialize',
      'initialized',
      ...defaultMethods,
      'shutdown',
      'exit'
    ]);
    expect(summary.counts).toEqual(Object.fromEntries(defaultMethods.map(method => [method, 1])));
    expect(summary.serverInfo).toEqual({ name: 'PhoenixLS', version: '0.1.0' });
    expect(summary.stderr).toBe('');
  });

  test('fails when a required explorer payload is empty', async () => {
    const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-dogfood-root-'));
    const serverPath = path.join(rootDir, 'phoenix_ls');
    fs.writeFileSync(serverPath, '#!/bin/sh\n');
    fs.chmodSync(serverPath, 0o755);

    const results = completeExplorerResults();
    results['phoenix/listTemplates'] = [];

    await expect(
      dogfoodBundledServer({
        rootDir,
        serverPath,
        spawn: createFakeServerSpawn({ results })
      })
    ).rejects.toThrow('missing non-empty dogfood results for phoenix/listTemplates');
  });

  test('fails when listRoutes omits route contract fields', async () => {
    const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-dogfood-root-'));
    const serverPath = path.join(rootDir, 'phoenix_ls');
    fs.writeFileSync(serverPath, '#!/bin/sh\n');
    fs.chmodSync(serverPath, 0o755);

    const results = completeExplorerResults();
    results['phoenix/listRoutes'] = [{}];

    await expect(
      dogfoodBundledServer({
        rootDir,
        serverPath,
        spawn: createFakeServerSpawn({ results })
      })
    ).rejects.toThrow(
      'phoenix/listRoutes[0] missing contract fields: verb, path, filePath, location, helperBase, helperName, helperVariants, pathParams, pipelines'
    );
  });

  test('fails when listSchemas omits schema contract fields', async () => {
    const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-dogfood-root-'));
    const serverPath = path.join(rootDir, 'phoenix_ls');
    fs.writeFileSync(serverPath, '#!/bin/sh\n');
    fs.chmodSync(serverPath, 0o755);

    const results = completeExplorerResults();
    results['phoenix/listSchemas'] = [{}];

    await expect(
      dogfoodBundledServer({
        rootDir,
        serverPath,
        spawn: createFakeServerSpawn({ results })
      })
    ).rejects.toThrow(
      'phoenix/listSchemas[0] missing contract fields: module, table, filePath, location, fields, associations'
    );
  });

  test('fails when listComponents omits component contract fields', async () => {
    const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-dogfood-root-'));
    const serverPath = path.join(rootDir, 'phoenix_ls');
    fs.writeFileSync(serverPath, '#!/bin/sh\n');
    fs.chmodSync(serverPath, 0o755);

    const results = completeExplorerResults();
    results['phoenix/listComponents'] = [{}];

    await expect(
      dogfoodBundledServer({
        rootDir,
        serverPath,
        spawn: createFakeServerSpawn({ results })
      })
    ).rejects.toThrow(
      'phoenix/listComponents[0] missing contract fields: module, name, filePath, location, attributes, slots'
    );
  });

  test('fails when listTemplates omits template contract fields', async () => {
    const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-dogfood-root-'));
    const serverPath = path.join(rootDir, 'phoenix_ls');
    fs.writeFileSync(serverPath, '#!/bin/sh\n');
    fs.chmodSync(serverPath, 0o755);

    const results = completeExplorerResults();
    results['phoenix/listTemplates'] = [{}];

    await expect(
      dogfoodBundledServer({
        rootDir,
        serverPath,
        spawn: createFakeServerSpawn({ results })
      })
    ).rejects.toThrow(
      'phoenix/listTemplates[0] missing contract fields: name, format, kind, module, filePath, location'
    );
  });

  test('fails when listEvents omits event contract fields', async () => {
    const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-dogfood-root-'));
    const serverPath = path.join(rootDir, 'phoenix_ls');
    fs.writeFileSync(serverPath, '#!/bin/sh\n');
    fs.chmodSync(serverPath, 0o755);

    const results = completeExplorerResults();
    results['phoenix/listEvents'] = [{}];

    await expect(
      dogfoodBundledServer({
        rootDir,
        serverPath,
        spawn: createFakeServerSpawn({ results })
      })
    ).rejects.toThrow(
      'phoenix/listEvents[0] missing contract fields: name, type, handler, arity, module, source, filePath, location'
    );
  });

  test('fails when listLiveView omits LiveView contract fields', async () => {
    const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-ls-dogfood-root-'));
    const serverPath = path.join(rootDir, 'phoenix_ls');
    fs.writeFileSync(serverPath, '#!/bin/sh\n');
    fs.chmodSync(serverPath, 0o755);

    const results = completeExplorerResults();
    results['phoenix/listLiveView'] = [{}];

    await expect(
      dogfoodBundledServer({
        rootDir,
        serverPath,
        spawn: createFakeServerSpawn({ results })
      })
    ).rejects.toThrow(
      'phoenix/listLiveView[0] missing contract fields: module, filePath, location, assigns, functions'
    );
  });
});

function completeExplorerResults() {
  return {
    'phoenix/listSchemas': [
      {
        module: 'App.Catalog.Product',
        table: 'products',
        filePath: '/workspace/lib/app/catalog/product.ex',
        location: { line: 3, character: 2 },
        fields: [],
        associations: []
      }
    ],
    'phoenix/listComponents': [
      {
        module: 'AppWeb.CoreComponents',
        name: 'button',
        filePath: '/workspace/lib/app_web/components/core_components.ex',
        location: { line: 8, character: 2 },
        attributes: [],
        slots: []
      }
    ],
    'phoenix/listRoutes': [
      {
        verb: 'GET',
        path: '/products/:id',
        controller: 'AppWeb.ProductController',
        action: 'show',
        helperBase: 'product',
        helperName: 'product_path',
        helperPrefix: null,
        helperVariants: ['path', 'url'],
        pathParams: ['id'],
        pipelines: ['browser'],
        pipeline: 'browser',
        filePath: '/workspace/lib/app_web/router.ex',
        location: { line: 42, character: 4 },
        scopePath: '/'
      }
    ],
    'phoenix/listTemplates': [
      {
        name: 'index.html',
        format: 'heex',
        kind: 'controller',
        module: 'AppWeb.PageHTML',
        filePath: '/workspace/lib/app_web/controllers/page_html/index.html.heex',
        location: { line: 0, character: 0 }
      }
    ],
    'phoenix/listEvents': [
      {
        name: 'save',
        type: 'handle_event',
        handler: 'handle_event/3',
        arity: 3,
        module: 'AppWeb.ProductLive.Index',
        source: 'handler',
        filePath: '/workspace/lib/app_web/live/product_live/index.ex',
        location: { line: 48, character: 4 }
      }
    ],
    'phoenix/listLiveView': [
      {
        module: 'AppWeb.ProductLive.Index',
        filePath: '/workspace/lib/app_web/live/product_live/index.ex',
        location: { line: 1, character: 2 },
        assigns: [],
        functions: []
      }
    ]
  };
}

function createFakeServerSpawn({ results }) {
  const calls = [];
  const requests = [];

  function spawn(command, args, options) {
    calls.push({ command, args, ...options });

    const stdout = new EventEmitter();
    const stderr = new EventEmitter();
    const child = new EventEmitter();
    child.stdout = stdout;
    child.stderr = stderr;
    child.kill = () => {
      child.killed = true;
    };

    let input = Buffer.alloc(0);

    child.stdin = {
      write(chunk) {
        input = Buffer.concat([input, Buffer.from(chunk)]);
        for (const message of readMessages()) {
          requests.push(message);
          handleMessage(message);
        }
      },
      end() {}
    };

    function handleMessage(message) {
      if (!Object.prototype.hasOwnProperty.call(message, 'id')) return;

      if (message.method === 'initialize') {
        emitMessage(stdout, {
          jsonrpc: '2.0',
          id: message.id,
          result: { serverInfo: { name: 'PhoenixLS', version: '0.1.0' } }
        });
      } else if (message.method === 'shutdown') {
        emitMessage(stdout, { jsonrpc: '2.0', id: message.id, result: null });
        queueMicrotask(() => child.emit('exit', 0, null));
      } else {
        emitMessage(stdout, {
          jsonrpc: '2.0',
          id: message.id,
          result: results[message.method] || []
        });
      }
    }

    function readMessages() {
      const messages = [];

      while (true) {
        const headerEnd = input.indexOf('\r\n\r\n');
        if (headerEnd === -1) break;

        const header = input.slice(0, headerEnd).toString('utf8');
        const length = Number(header.slice('Content-Length:'.length).trim());
        const bodyStart = headerEnd + 4;
        const bodyEnd = bodyStart + length;
        if (input.length < bodyEnd) break;

        messages.push(JSON.parse(input.slice(bodyStart, bodyEnd).toString('utf8')));
        input = input.slice(bodyEnd);
      }

      return messages;
    }

    return child;
  }

  spawn.calls = calls;
  spawn.requests = requests;

  return spawn;
}

function emitMessage(stream, message) {
  const body = Buffer.from(JSON.stringify(message), 'utf8');
  stream.emit(
    'data',
    Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, 'utf8'), body])
  );
}
