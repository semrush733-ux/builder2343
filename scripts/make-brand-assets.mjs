#!/usr/bin/env node
/*
 * BWP Billing - build the icon and splash SOURCE images from one logo.
 *
 * Input :  assets/logo.png        (transparent PNG, 1024px or larger)
 * Output:  assets/icon-only.png        1024x1024  flat icon (iOS, legacy Android), no transparency
 *          assets/icon-foreground.png  1024x1024  Android adaptive icon foreground
 *          assets/icon-background.png  1024x1024  Android adaptive icon background
 *          assets/splash.png           2732x2732  splash: logo + "BWP Billing / by BWP Experts"
 *          assets/splash-dark.png      2732x2732  same artwork (the logo needs a light background)
 *          src/logo.png                 512x512   logo used by the launch / error screens
 *
 * The logo is trimmed and scaled proportionally - it is never stretched.
 * `npm run brand` runs this and then `capacitor-assets generate`, which produces every
 * Android / iOS resolution from these source images.
 */
import { createRequire } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const root = join(dirname(fileURLToPath(import.meta.url)), '..');

let sharp;
try {
  sharp = require('sharp');
} catch (e) {
  console.error('The "sharp" image library is missing. Run "npm install" first.');
  process.exit(1);
}

const app = JSON.parse(readFileSync(join(root, 'src', 'app-config.json'), 'utf8'));
const background = app.backgroundColor || '#FFFFFF';
const brand = app.brandColor || '#014F4A';
const logoFile = join(root, 'assets', 'logo.png');

if (!existsSync(logoFile)) {
  console.error('assets/logo.png not found.');
  process.exit(1);
}

const escapeXml = (s) => String(s).replace(/[<>&"']/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' }[c]));

/** Logo trimmed to its artwork and scaled to fit inside box x box (aspect ratio kept). */
async function fitted(box) {
  const trimmed = await sharp(logoFile).ensureAlpha().trim().png().toBuffer();
  return sharp(trimmed)
    .resize(box, box, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();
}

async function canvas(size, color, layers, file, flatten) {
  let image = sharp({ create: { width: size, height: size, channels: 4, background: color } }).composite(layers);
  if (flatten) image = image.flatten({ background }).removeAlpha();
  await image.png({ compressionLevel: 9 }).toFile(join(root, file));
  console.log('  wrote', file);
}

const transparent = { r: 0, g: 0, b: 0, alpha: 0 };
const centered = (size, box) => Math.round((size - box) / 2);

async function main() {
  console.log('Building brand source images from assets/logo.png');

  // Flat icon: logo fills ~78% of the square.
  let box = 800;
  await canvas(1024, background, [{ input: await fitted(box), left: centered(1024, box), top: centered(1024, box) }], 'assets/icon-only.png', true);

  // Adaptive icon: Android masks the outer part, so the logo stays inside the central safe zone.
  box = 580;
  await canvas(1024, transparent, [{ input: await fitted(box), left: centered(1024, box), top: centered(1024, box) }], 'assets/icon-foreground.png', false);
  await canvas(1024, background, [], 'assets/icon-background.png', true);

  // Splash: everything sits in the middle third so it survives cropping on every screen shape.
  const size = 2732;
  box = 560;
  const logoTop = 900;
  const text = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}">
       <text x="50%" y="${logoTop + box + 150}" text-anchor="middle" font-family="Segoe UI, Roboto, Helvetica Neue, Arial, DejaVu Sans, sans-serif" font-weight="700" font-size="132" fill="${brand}">${escapeXml(app.appName)}</text>
       <text x="50%" y="${logoTop + box + 250}" text-anchor="middle" font-family="Segoe UI, Roboto, Helvetica Neue, Arial, DejaVu Sans, sans-serif" font-weight="400" font-size="64" fill="#4B6663">by ${escapeXml(app.company)}</text>
     </svg>`
  );
  const splashLayers = [
    { input: await fitted(box), left: centered(size, box), top: logoTop },
    { input: text, left: 0, top: 0 },
  ];
  await canvas(size, background, splashLayers, 'assets/splash.png', true);
  await canvas(size, background, splashLayers, 'assets/splash-dark.png', true);

  // Logo for the in-app launch / error screens.
  await sharp(await fitted(512)).png({ compressionLevel: 9 }).toFile(join(root, 'src', 'logo.png'));
  console.log('  wrote src/logo.png');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
