import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';

export interface ResolvedServer {
  command: string;
  args: string[];
  env: NodeJS.ProcessEnv;
}

function isExecutableFile(candidate: string, outputChannel: vscode.OutputChannel): boolean {
  try {
    const stat = fs.statSync(candidate);

    if (!stat.isFile()) {
      outputChannel.appendLine(`Phoenix LS candidate is not a file: ${candidate}`);
      return false;
    }

    fs.accessSync(candidate, fs.constants.X_OK);
    return true;
  } catch (error) {
    if (fs.existsSync(candidate)) {
      outputChannel.appendLine(`Phoenix LS candidate is not executable: ${candidate}`);
    }

    return false;
  }
}

export function resolveServer(
  context: vscode.ExtensionContext,
  outputChannel: vscode.OutputChannel
): ResolvedServer | undefined {
  const config = vscode.workspace.getConfiguration('phoenixPulse');
  const configuredPath = config.get<string>('serverPath', '').trim();
  const envPath = process.env.PHOENIX_LS_SERVER_PATH?.trim() || '';

  const candidates = [
    configuredPath,
    envPath,
    context.asAbsolutePath(path.join('server', 'phoenix_ls')),
    context.asAbsolutePath(path.join('bin', 'phoenix_ls')),
    context.asAbsolutePath(path.join('..', '..', 'server', 'apps', 'phoenix_ls', 'phoenix_ls'))
  ].filter((candidate): candidate is string => candidate.length > 0);

  const command = candidates.find(candidate => isExecutableFile(candidate, outputChannel));

  if (!command) {
    outputChannel.appendLine('Phoenix LS executable not found. Checked:');

    for (const candidate of candidates) {
      outputChannel.appendLine(`  ${candidate}`);
    }

    return undefined;
  }

  const sourceOnlyMode = config.get<boolean>('sourceOnlyMode', true);
  const logLevel = config.get<string>('logLevel', 'info');
  const indexingEnabled = config.get<boolean>('indexing.enabled', true);

  return {
    command,
    args: ['--stdio'],
    env: {
      ...process.env,
      PHOENIX_LS_SOURCE_ONLY: sourceOnlyMode ? '1' : '0',
      PHOENIX_LS_LOG_LEVEL: logLevel,
      PHOENIX_LS_INDEXING: indexingEnabled ? '1' : '0'
    }
  };
}
