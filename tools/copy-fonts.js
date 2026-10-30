// Copies the Fredoka font (OFL licence) from node_modules into www/fonts so the app works fully offline.
const fs = require('fs');
const path = require('path');

const src = path.join(__dirname, '..', 'node_modules', '@fontsource', 'fredoka', 'files');
const dst = path.join(__dirname, '..', 'www', 'fonts');
fs.mkdirSync(dst, { recursive: true });

for (const w of [500, 600, 700]) {
  const from = path.join(src, `fredoka-latin-${w}-normal.woff2`);
  if (!fs.existsSync(from)) {
    console.error('Font file not found:', from);
    process.exit(1);
  }
  fs.copyFileSync(from, path.join(dst, `fredoka-${w}.woff2`));
  console.log('font copied:', w);
}
