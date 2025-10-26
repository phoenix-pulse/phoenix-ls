const esbuild = require('esbuild');

const production = process.argv.includes('--production');
const watch = process.argv.includes('--watch');

async function main() {
  const ctx = await esbuild.context({
    entryPoints: ['src/server.ts'],
    bundle: true,
    format: 'cjs',
    minify: production,
    sourcemap: !production,
    sourcesContent: false,
    platform: 'node',
    outfile: 'dist/server.js',
    external: ['@vscode/emmet-helper', 'web-tree-sitter'],
    logLevel: 'info',
    loader: {
      '.ts': 'ts'
    }
  });

  if (watch) {
    await ctx.watch();
    console.log('Watching LSP server for changes...');
  } else {
    await ctx.rebuild();
    await ctx.dispose();
  }
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
