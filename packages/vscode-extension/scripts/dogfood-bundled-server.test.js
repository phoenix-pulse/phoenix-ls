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
      'phoenix/listRoutes[0] missing contract fields: verb, path, filePath, location, helperBase, pathParams, pipelines'
    );
  });
});

function completeExplorerResults() {
  return {
    'phoenix/listSchemas': [{ method: 'phoenix/listSchemas' }],
    'phoenix/listComponents': [{ method: 'phoenix/listComponents' }],
    'phoenix/listRoutes': [
      {
        verb: 'GET',
        path: '/products/:id',
        controller: 'AppWeb.ProductController',
        action: 'show',
        helperBase: 'product',
        pathParams: ['id'],
        pipelines: ['browser'],
        pipeline: 'browser',
        filePath: '/workspace/lib/app_web/router.ex',
        location: { line: 42, character: 4 },
        scopePath: '/'
      }
    ],
    'phoenix/listTemplates': [{ method: 'phoenix/listTemplates' }],
    'phoenix/listEvents': [{ method: 'phoenix/listEvents' }],
    'phoenix/listLiveView': [{ method: 'phoenix/listLiveView' }]
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
