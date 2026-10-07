#!/usr/bin/env node
/*
 * App builder - turns one build request into a project configuration.
 * Used by .github/workflows/build-app.yml (started from the WordPress "BWP App Builder" plugin).
 *
 * Input (environment):
 *   BUILD_CONFIG  JSON: { appName, homeUrl, appId?, company?, brandColor?, backgroundColor?,
 *                         loadingText?, extraHosts?: string[] }
 *   LOGO_URL      optional https URL of the logo image (PNG / JPG / WebP)
 *
 * Every value is validated here; nothing from the request is ever executed or interpolated
 * into a shell command.
 *
 * Output:
 *   src/app-config.json, src/index.html + src/error.html (static texts), assets/logo.png
 *   $GITHUB_ENV:  APP_SLUG, APP_NAME, APP_ID          build-warnings.txt (one warning per line)
 */
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const warnings = [];

function fail(message) {
  console.error(`BUILD CONFIG ERROR: ${message}`);
  try { writeFileSync(join(root, 'build-error.txt'), message + '\n'); } catch (e) { /* ignore */ }
  process.exit(1);
}

let request;
try {
  request = JSON.parse(process.env.BUILD_CONFIG || '');
} catch (e) {
  fail('The build request is not valid JSON.');
}
if (!request || typeof request !== 'object' || Array.isArray(request)) fail('The build request is empty.');

const text = (value, max) => String(value == null ? '' : value).replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);

// ---- app name: shown under the icon, so keep it short and free of markup characters
const appName = text(request.appName, 60).replace(/[<>&"'`\\\/{}$%]/g, '').replace(/\s+/g, ' ').trim().slice(0, 30);
if (appName.length < 2) fail('App name is required (2 to 30 characters).');

// ---- website: https only
let home;
try {
  home = new URL(text(request.homeUrl, 500));
} catch (e) {
  fail('Website URL is not valid.');
}
if (home.protocol !== 'https:') fail('Website URL must start with https://');
if (home.username || home.password) fail('Website URL must not contain a user name or password.');
const host = home.hostname.toLowerCase();
const hostPattern = /^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$/;
if (!hostPattern.test(host)) fail('Website URL must use a public domain name.');
home.hash = '';

// ---- hosts that stay inside the app: the site itself, its www / non-www twin, and listed extras
const hosts = [host, host.startsWith('www.') ? host.slice(4) : `www.${host}`];
for (const extra of Array.isArray(request.extraHosts) ? request.extraHosts.slice(0, 5) : []) {
  const candidate = text(extra, 253).toLowerCase().replace(/^https?:\/\//, '').replace(/\/.*$/, '');
  if (hostPattern.test(candidate) && !hosts.includes(candidate)) hosts.push(candidate);
}

// ---- app ID (Android package / iOS bundle ID)
const reserved = new Set(('abstract assert boolean break byte case catch char class const continue default do double else enum extends ' +
  'false final finally float for goto if implements import instanceof int interface long native new null package private protected ' +
  'public return short static strictfp super switch synchronized this throw throws transient true try void volatile while').split(' '));
const segment = (part) => {
  let s = part.toLowerCase().replace(/[^a-z0-9]/g, '');
  if (!s) return '';
  if (/^[0-9]/.test(s)) s = `a${s}`;
  if (reserved.has(s)) s = `${s}app`;
  return s.slice(0, 30);
};
function deriveAppId() {
  const parts = host.replace(/^www\./, '').split('.').reverse().map(segment).filter(Boolean);
  return [...parts, 'app'].slice(0, 6).join('.');
}
let appId = text(request.appId, 150).toLowerCase();
if (appId) {
  const parts = appId.split('.').map(segment);
  if (parts.length < 2 || parts.length > 6 || parts.some((p) => !p)) {
    warnings.push(`App ID "${appId}" is not valid; "${deriveAppId()}" was used instead.`);
    appId = deriveAppId();
  } else {
    appId = parts.join('.');
  }
} else {
  appId = deriveAppId();
}

// ---- colours and texts
const hex = (value, fallback) => (/^#[0-9a-f]{6}$/i.test(text(value, 7)) ? text(value, 7).toUpperCase() : fallback);
const brandColor = hex(request.brandColor, '#1F2937');
const backgroundColor = hex(request.backgroundColor, '#FFFFFF');
const company = text(request.company, 60).replace(/[<>&"'`\\{}$%]/g, '').trim().slice(0, 40);
const loadingText = text(request.loadingText, 80).replace(/[<>&"'`\\{}$%]/g, '').trim().slice(0, 60) || 'Loading...';

const config = {
  appName,
  appId,
  company,
  homeUrl: home.href,
  allowedHosts: hosts,
  brandColor,
  backgroundColor,
  loadingText,
  pullToRefresh: request.pullToRefresh !== false,
  downloadExtensions: ['pdf', 'csv', 'xls', 'xlsx', 'doc', 'docx', 'zip'],
  secureScreenPaths: [],
};
writeFileSync(join(root, 'src', 'app-config.json'), JSON.stringify(config, null, 2) + '\n');

// ---- static texts of the launch / error screens (shown before the config file is read)
const escapeHtml = (s) => s.replace(/[<>&"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c]));
for (const file of ['index.html', 'error.html']) {
  const path = join(root, 'src', file);
  let html = readFileSync(path, 'utf8');
  html = html
    .replace(/<title>[^<]*<\/title>/, `<title>${escapeHtml(appName)}</title>`)
    .replace(/(<h1 id="app-name">)[^<]*(<\/h1>)/, `$1${escapeHtml(appName)}$2`)
    .replace(/(<p id="app-company")[^>]*>[^<]*(<\/p>)/, company ? `$1>by ${escapeHtml(company)}$2` : '$1 hidden>$2')
    .replace(/(<h2 id="unreachable-title">)[^<]*(<\/h2>)/, `$1We couldn't connect to ${escapeHtml(appName)}.$2`)
    .replace(/(<p class="hint" id="loading-text">)[^<]*(<\/p>)/, `$1${escapeHtml(loadingText)}$2`)
    .replace(/(<meta name="theme-color" content=")[^"]*(">)/, `$1${backgroundColor}$2`)
    .replace(/(<link rel="preconnect" href=")[^"]*(">)/, `$1${home.origin}$2`);
  writeFileSync(path, html);
}

// ---- logo
async function downloadLogo(url) {
  let parsed;
  try { parsed = new URL(url); } catch (e) { throw new Error('the logo address is not a valid URL'); }
  if (parsed.protocol !== 'https:') throw new Error('the logo address must start with https://');
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  try {
    const res = await fetch(parsed, { signal: controller.signal, redirect: 'follow', headers: { 'User-Agent': 'bwp-app-builder' } });
    if (!res.ok) throw new Error(`the logo could not be downloaded (HTTP ${res.status})`);
    const length = Number(res.headers.get('content-length') || 0);
    if (length > 8 * 1024 * 1024) throw new Error('the logo file is larger than 8 MB');
    const buffer = Buffer.from(await res.arrayBuffer());
    if (buffer.length > 8 * 1024 * 1024) throw new Error('the logo file is larger than 8 MB');
    return buffer;
  } finally {
    clearTimeout(timer);
  }
}

async function writeLogo() {
  let sharp;
  try { sharp = require('sharp'); } catch (e) { fail('The image library is missing (run npm install first).'); }
  const target = join(root, 'assets', 'logo.png');
  const logoUrl = text(process.env.LOGO_URL, 1000);

  if (logoUrl) {
    try {
      const input = await downloadLogo(logoUrl);
      const meta = await sharp(input).metadata();
      if (!meta.width || !meta.height) throw new Error('the logo is not a readable image');
      if (Math.max(meta.width, meta.height) < 200) warnings.push('The logo is small (under 200 px); the icon may look blurry.');
      await sharp(input).rotate().ensureAlpha()
        .resize(1024, 1024, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
        .png().toFile(target);
      return;
    } catch (e) {
      warnings.push(`Logo not used: ${e.message}. A letter icon was created instead.`);
    }
  } else {
    warnings.push('No logo was supplied; a letter icon was created.');
  }

  // Fallback: first letter of the app name on a rounded square in the brand colour.
  const letter = escapeHtml((appName.match(/[\p{L}\p{N}]/u) || ['A'])[0].toUpperCase());
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024">
    <rect x="112" y="112" width="800" height="800" rx="180" fill="${brandColor}"/>
    <text x="512" y="690" text-anchor="middle" font-family="Helvetica Neue, Arial, DejaVu Sans, sans-serif" font-weight="700" font-size="520" fill="#FFFFFF">${letter}</text>
  </svg>`;
  await sharp(Buffer.from(svg)).png().toFile(target);
}

await writeLogo();

// ---- hand the results to the following workflow steps
const slug = (appName.normalize('NFKD').replace(/[^\x20-\x7e]/g, '').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'app').slice(0, 40);
if (process.env.GITHUB_ENV) {
  appendFileSync(process.env.GITHUB_ENV, `APP_SLUG=${slug}\nAPP_ID=${appId}\n`);
}
writeFileSync(join(root, 'build-warnings.txt'), warnings.join('\n') + (warnings.length ? '\n' : ''));

console.log('Build configuration applied:');
console.log(JSON.stringify({ ...config, slug }, null, 2));
if (warnings.length) console.log('Warnings:\n  - ' + warnings.join('\n  - '));
