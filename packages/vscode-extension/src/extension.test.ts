import fs from 'fs';
import path from 'path';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const vscodeState = vi.hoisted(() => ({
  config: {
    mode: 'auto',
    detectExpert: true,
    disableGenericElixir: true
  },
  expertExtension: undefined as unknown,
  elixirLSExtension: undefined as unknown,
  allExtensions: [] as Array<{ id: string; packageJSON?: Record<string, unknown> }>
}));

const getExtension = vi.hoisted(() => vi.fn());

vi.mock('vscode', () => ({
  workspace: {
    getConfiguration: vi.fn((section: string) => ({
      get: vi.fn((key: string, defaultValue?: unknown) => {
        if (section === 'phoenixLS' && key === 'mode') return vscodeState.config.mode;
        if (section === 'phoenixLS' && key === 'companion.detectExpert') return vscodeState.config.detectExpert;
        if (section === 'phoenixLS' && key === 'companion.disableGenericElixir') {
          return vscodeState.config.disableGenericElixir;
        }
        return defaultValue;
      })
    })),
    createFileSystemWatcher: vi.fn()
  },
  extensions: {
    getExtension,
    get all() {
      return vscodeState.allExtensions;
    }
  },
  window: {
    createOutputChannel: vi.fn(),
    showErrorMessage: vi.fn(),
    showInformationMessage: vi.fn(),
    createTreeView: vi.fn()
  },
  commands: {
    registerCommand: vi.fn(),
    executeCommand: vi.fn()
  },
  env: {
    clipboard: {
      writeText: vi.fn()
    }
  },
  Uri: {
    file: vi.fn((filePath: string) => ({ fsPath: filePath })),
    parse: vi.fn((value: string) => ({ fsPath: value }))
  },
  Position: class {
    constructor(public line: number, public character: number) {}
  },
  Range: class {
    constructor(public start: unknown, public end: unknown) {}
  },
  EventEmitter: class {
    event = vi.fn();
    fire = vi.fn();
    dispose = vi.fn();
  },
  TreeItem: class {
    constructor(public label: unknown, public collapsibleState?: unknown) {}
  },
  TreeItemCollapsibleState: {
    None: 0,
    Collapsed: 1,
    Expanded: 2
  },
  ThemeIcon: class {
    constructor(public id: string, public color?: unknown) {}
  },
  ThemeColor: class {
    constructor(public id: string) {}
  },
  ViewColumn: {
    One: 1
  },
  Location: class {
    constructor(public uri: unknown, public range: unknown) {}
  },
  Selection: class {
    constructor(public start: unknown, public end: unknown) {}
  },
  TextEditorRevealType: {
    InCenter: 1
  }
}));

vi.mock('vscode-languageclient/node', () => ({
  LanguageClient: class {
    onDidChangeState() {}
    start() {
      return Promise.resolve();
    }
    stop() {
      return Promise.resolve();
    }
  },
  DefinitionRequest: {
    type: 'textDocument/definition'
  }
}));

import {
  buildPhoenixLSServerOptions,
  describePhoenixLSMode,
  resolvePhoenixLSMode
} from './extension';

describe('Phoenix LS VS Code companion mode', () => {
  beforeEach(() => {
    vscodeState.config = {
      mode: 'auto',
      detectExpert: true,
      disableGenericElixir: true
    };
    vscodeState.expertExtension = undefined;
    vscodeState.elixirLSExtension = undefined;
    vscodeState.allExtensions = [];
    getExtension.mockReset();
    getExtension.mockImplementation((id: string) => {
      if (id === 'ExpertLSP.expert') return vscodeState.expertExtension;
      if (id === 'JakeBecker.elixir-ls') return vscodeState.elixirLSExtension;
      return undefined;
    });
  });

  it('resolves auto mode to companion and exports env when Expert is detected', () => {
    vscodeState.expertExtension = { id: 'ExpertLSP.expert' };

    const mode = resolvePhoenixLSMode();

    expect(getExtension).toHaveBeenCalledWith('ExpertLSP.expert');
    expect(mode).toMatchObject({
      configuredMode: 'auto',
      resolvedMode: 'companion',
      detectedExpert: true,
      disableGenericElixir: true,
      env: {
        PHOENIX_LS_MODE: 'auto',
        PHOENIX_LS_DETECTED_EXPERT: 'true',
        PHOENIX_LS_DETECTED_COMPANION_PEER: 'true',
        PHOENIX_LS_DISABLE_GENERIC_ELIXIR: 'true'
      }
    });
    expect(describePhoenixLSMode(mode)).toBe('Phoenix LS mode: companion (Expert detected)');
  });

  it('detects Expert from the installed extension registry when direct lookup misses', () => {
    vscodeState.allExtensions = [
      {
        id: 'expertlsp.expert',
        packageJSON: {
          displayName: 'Expert LSP',
          description: 'Official Elixir language server'
        }
      }
    ];

    const mode = resolvePhoenixLSMode();

    expect(mode).toMatchObject({
      configuredMode: 'auto',
      resolvedMode: 'companion',
      detectedExpert: true,
      detectedCompanionPeer: true,
      env: {
        PHOENIX_LS_DETECTED_EXPERT: 'true',
        PHOENIX_LS_DETECTED_COMPANION_PEER: 'true'
      }
    });
    expect(describePhoenixLSMode(mode)).toBe('Phoenix LS mode: companion (Expert detected)');
  });

  it('detects Expert from lowercase VS Code extension IDs', () => {
    getExtension.mockImplementation((id: string) => {
      if (id === 'expertlsp.expert') return { id: 'expertlsp.expert' };
      return undefined;
    });

    const mode = resolvePhoenixLSMode();

    expect(getExtension).toHaveBeenCalledWith('ExpertLSP.expert');
    expect(getExtension).toHaveBeenCalledWith('expertlsp.expert');
    expect(mode.detectedExpert).toBe(true);
    expect(mode.resolvedMode).toBe('companion');
  });

  it('resolves auto mode to companion when ElixirLS is detected without Expert', () => {
    vscodeState.elixirLSExtension = { id: 'JakeBecker.elixir-ls' };

    const mode = resolvePhoenixLSMode();

    expect(getExtension).toHaveBeenCalledWith('ExpertLSP.expert');
    expect(getExtension).toHaveBeenCalledWith('JakeBecker.elixir-ls');
    expect(mode).toMatchObject({
      configuredMode: 'auto',
      resolvedMode: 'companion',
      detectedExpert: false,
      detectedGenericElixirLS: true,
      detectedCompanionPeer: true,
      disableGenericElixir: true,
      env: {
        PHOENIX_LS_MODE: 'auto',
        PHOENIX_LS_DETECTED_EXPERT: 'false',
        PHOENIX_LS_DETECTED_COMPANION_PEER: 'true',
        PHOENIX_LS_DISABLE_GENERIC_ELIXIR: 'true'
      }
    });
    expect(describePhoenixLSMode(mode)).toBe('Phoenix LS mode: companion (ElixirLS detected)');
  });

  it('does not inspect Expert when detection is disabled', () => {
    vscodeState.config.detectExpert = false;
    vscodeState.expertExtension = { id: 'ExpertLSP.expert' };

    const mode = resolvePhoenixLSMode();

    expect(getExtension).not.toHaveBeenCalled();
    expect(mode).toMatchObject({
      configuredMode: 'auto',
      resolvedMode: 'full',
      detectedExpert: false,
      env: {
        PHOENIX_LS_DETECTED_EXPERT: 'false',
        PHOENIX_LS_DETECTED_COMPANION_PEER: 'false'
      }
    });
    expect(describePhoenixLSMode(mode)).toBe('Phoenix LS mode: full (companion detection disabled)');
  });

  it('preserves resolver env values and keeps debug log override behavior', () => {
    vscodeState.config.mode = 'full';
    vscodeState.config.disableGenericElixir = false;
    vscodeState.expertExtension = { id: 'ExpertLSP.expert' };

    const mode = resolvePhoenixLSMode();
    const serverOptions = buildPhoenixLSServerOptions({
      command: '/tmp/phoenix_ls',
      args: ['--stdio'],
      env: {
        PHOENIX_LS_LOG_LEVEL: 'info',
        PHOENIX_LS_INDEXING: '1',
        CUSTOM_ENV: 'kept'
      }
    });

    expect(serverOptions.run.options.env).toMatchObject({
      CUSTOM_ENV: 'kept',
      PHOENIX_LS_INDEXING: '1',
      PHOENIX_LS_LOG_LEVEL: 'info',
      PHOENIX_LS_MODE: mode.env.PHOENIX_LS_MODE,
      PHOENIX_LS_DETECTED_EXPERT: 'true',
      PHOENIX_LS_DETECTED_COMPANION_PEER: 'true',
      PHOENIX_LS_DISABLE_GENERIC_ELIXIR: 'false'
    });
    expect(serverOptions.debug.options.env).toMatchObject({
      CUSTOM_ENV: 'kept',
      PHOENIX_LS_MODE: 'full',
      PHOENIX_LS_LOG_LEVEL: 'debug'
    });
  });

  it('contributes Phoenix LS companion settings', () => {
    const packageJson = JSON.parse(
      fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8')
    );

    expect(packageJson.contributes.configuration.properties).toMatchObject({
      'phoenixLS.mode': {
        type: 'string',
        enum: ['auto', 'companion', 'full'],
        default: 'auto'
      },
      'phoenixLS.companion.detectExpert': {
        type: 'boolean',
        default: true
      },
      'phoenixLS.companion.disableGenericElixir': {
        type: 'boolean',
        default: true
      }
    });
  });

  it('contributes HEEx editor defaults for HTML-adjacent tooling', () => {
    const packageJson = JSON.parse(
      fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8')
    );

    expect(packageJson.contributes.configurationDefaults).toMatchObject({
      'emmet.includeLanguages': {
        'phoenix-heex': 'html'
      },
      'tailwindCSS.includeLanguages': {
        'phoenix-heex': 'html'
      }
    });
  });

  it('contributes Explorer copy actions for every advertised item kind', () => {
    const packageJson = JSON.parse(
      fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8')
    );

    const contextMenus = packageJson.contributes.menus['view/item/context'];
    const copyNameWhen = contextMenus.find(
      (item: { command: string }) => item.command === 'phoenixPulse.copyName'
    ).when;
    const copyFilePathWhen = contextMenus.find(
      (item: { command: string }) => item.command === 'phoenixPulse.copyFilePath'
    ).when;

    for (const itemKind of [
      'schema',
      'schema-field',
      'schema-association',
      'component',
      'component-attribute',
      'component-slot',
      'component-slot-attribute',
      'route',
      'template',
      'event',
      'controller',
      'controller-action',
      'controller-route',
      'controller-render',
      'controller-assign',
      'controller-plug-assign',
      'controller-layout',
      'liveview-module',
      'liveview-assign',
      'liveview-function'
    ]) {
      expect(copyNameWhen).toContain(itemKind);
      expect(copyFilePathWhen).toContain(itemKind);
    }
  });

  it('keeps the VS Code README scoped to implemented Phoenix LS behavior', () => {
    const readme = fs.readFileSync(path.join(__dirname, '..', 'README.md'), 'utf8');

    expect(readme).toContain('#### Controllers');
    expect(readme).not.toMatch(/complete IDE companion/i);
    expect(readme).not.toMatch(/entire Phoenix application/i);
    expect(readme).not.toMatch(/real-time metrics/i);
    expect(readme).not.toMatch(/First navigation: ~\d+ms/i);
    expect(readme).not.toMatch(/Subsequent: ~\d+-\d+ms/i);
    expect(readme).not.toMatch(/All \d+ `phx-\*` attributes/i);
    expect(readme).not.toMatch(/\| Nested Resources \| ✅ \| ✅ \|/);
    expect(readme).not.toMatch(/\| Singleton Resources \| ✅ \| ✅ \|/);
  });
});
