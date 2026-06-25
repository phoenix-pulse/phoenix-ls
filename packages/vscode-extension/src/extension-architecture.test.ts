import fs from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';

describe('VS Code launcher architecture', () => {
  it('does not inspect Phoenix dependency metadata in TypeScript', () => {
    const extensionSource = fs.readFileSync(path.join(__dirname, 'extension.ts'), 'utf8');

    expect(extensionSource).not.toContain('{:phoenix');
    expect(extensionSource).not.toContain('Phoenix dependency');
  });
});
