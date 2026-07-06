// Comment/whitespace stripping for the published assets.
//
// Usage: node minify.mjs <dist-dir>

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import * as esbuild from 'esbuild';
import { minify as minifyHtml } from 'html-minifier-terser';

const OUT = process.argv[2];
if (!OUT) {
  console.error('usage: node minify.mjs <dist-dir>');
  process.exit(1);
}

// CSS / JS: drop comments and collapse whitespace, but keep names and syntax.
for (const file of ['styles.css', 'script.js', 'sound.js', 'content.css', 'content.js']) {
  const path = join(OUT, file);
  if (!existsSync(path)) continue;
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

// HTML: remove comments (index.html plus every generated blog page).
const htmlFiles = [join(OUT, 'index.html')];
const blogDir = join(OUT, 'blog');
if (existsSync(blogDir)) {
  for (const name of readdirSync(blogDir)) {
    if (name.endsWith('.html')) htmlFiles.push(join(blogDir, name));
  }
}
for (const path of htmlFiles) {
  if (!existsSync(path)) continue;
  writeFileSync(path, await minifyHtml(readFileSync(path, 'utf8'), { removeComments: true }));
}

console.log('Stripped comments from CSS/JS/HTML.');
