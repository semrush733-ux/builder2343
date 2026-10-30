// Prepares www/ before a native build:
//  1. copies the Fredoka font (OFL licence) from node_modules into www/fonts (app works offline)
//  2. writes www/ads-config.js from ads.json (ad unit IDs used by the game)
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');

const src = path.join(root, 'node_modules', '@fontsource', 'fredoka', 'files');
const dst = path.join(root, 'www', 'fonts');
fs.mkdirSync(dst, { recursive: true });
for (const w of [500, 600, 700]) {
  const from = path.join(src, `fredoka-latin-${w}-normal.woff2`);
  if (!fs.existsSync(from)) { console.error('Font file not found:', from); process.exit(1); }
  fs.copyFileSync(from, path.join(dst, `fredoka-${w}.woff2`));
}
console.log('fonts copied');

const ads = JSON.parse(fs.readFileSync(path.join(root, 'ads.json'), 'utf8'));
const web = {
  testing: !!ads.testing,
  interEvery: ads.interEvery || 3,
  android: { reward: ads.android.reward, inter: ads.android.inter },
  ios: { reward: ads.ios.reward, inter: ads.ios.inter }
};
fs.writeFileSync(path.join(root, 'www', 'ads-config.js'), 'window.ADS_CONFIG=' + JSON.stringify(web) + ';\n');
console.log('ads-config.js written (testing=' + web.testing + ')');
