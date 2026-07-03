import { readFileSync, writeFileSync, rmSync, mkdirSync, cpSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import * as esbuild from 'esbuild';
import { minify as minifyHtml } from 'html-minifier-terser';

const ROOT = process.cwd();
const OUT = join(ROOT, 'dist');
const EXCLUDE = new Set([
  '.git', '.github', 'node_modules', 'dist',
  'design', 'tools',
  'package.json', 'package-lock.json', 'build.mjs', '.gitignore',
]);

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT);
for (const entry of readdirSync(ROOT)) {
  if (EXCLUDE.has(entry) || entry === '.DS_Store' || entry.endsWith('.md')) continue;
  cpSync(join(ROOT, entry), join(OUT, entry), {
    recursive: true,
    filter: (src) => !src.endsWith('.DS_Store'),
  });
}

for (const file of ['styles.css', 'script.js', 'sound.js']) {
  const path = join(OUT, file);
  const { code } = await esbuild.transform(readFileSync(path, 'utf8'), {
    loader: file.endsWith('.css') ? 'css' : 'js',
    minifyWhitespace: true,
    minifyIdentifiers: false,
    minifySyntax: false,
    legalComments: 'none',
  });
  const out = file.endsWith('.js') ? code.replace(/\/\*[\s\S]*?\*\//g, '') : code;
  writeFileSync(path, out);
}

const htmlPath = join(OUT, 'index.html');
writeFileSync(htmlPath, await minifyHtml(readFileSync(htmlPath, 'utf8'), {
  removeComments: true,
}));

console.log('Built dist/ (comments stripped).');
