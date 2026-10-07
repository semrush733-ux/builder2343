#!/usr/bin/env node
/*
 * BWP Billing - one-time project setup.
 *
 *   npm install
 *   npm run setup
 *
 * Creates the native projects (android/ and ios/) if they do not exist yet, generates every
 * icon / splash size, copies the web shell into them and applies the BWP-specific settings.
 * It is safe to run again at any time.
 */
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { root, run, fail } from './run.mjs';

const major = Number(process.versions.node.split('.')[0]);
if (major < 22) {
  fail(`Node.js 22 or newer is required (found ${process.versions.node}).`);
}
if (!existsSync(join(root, 'node_modules', '@capacitor', 'cli'))) {
  fail('Dependencies are not installed. Run "npm install" first.');
}

const hasAndroid = () => existsSync(join(root, 'android'));
const hasIos = () => existsSync(join(root, 'ios'));

if (!hasAndroid()) {
  if (!run('npx cap add android')) fail('Could not create the Android project.');
} else {
  console.log('android/ already exists - keeping it.');
}

if (!hasIos()) {
  // The Xcode project files can be created on any system; building them needs a Mac.
  if (!run('npx cap add ios')) {
    console.warn('\nWARNING: the iOS project could not be created on this computer.');
    console.warn('Run "npx cap add ios" and "npm run sync" on a Mac to create it.');
  }
} else {
  console.log('ios/ already exists - keeping it.');
}

const platforms = [hasAndroid() ? '--android' : '', hasIos() ? '--ios' : ''].filter(Boolean).join(' ');
if (platforms) {
  if (!run(`npx capacitor-assets generate ${platforms}`)) {
    console.warn('\nWARNING: icons / splash screens were not generated. Run "npm run brand" to retry.');
  }
}

if (!run('npx cap sync')) fail('"npx cap sync" failed.');
if (!run('node scripts/configure-native.mjs')) fail('Native configuration failed.');

console.log('\nSetup finished.');
console.log('  Android Studio : npm run android:open');
console.log('  Debug APK      : npm run android:debug');
console.log('  Xcode (Mac)    : npm run ios:open');
