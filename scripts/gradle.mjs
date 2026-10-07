#!/usr/bin/env node
/*
 * Runs a Gradle task of the Android project with the right wrapper for this system.
 *   node scripts/gradle.mjs assembleDebug | assembleRelease | bundleRelease | clean
 */
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { root, run, fail } from './run.mjs';

const task = process.argv[2];
if (!task) fail('Usage: node scripts/gradle.mjs <task>');

const android = join(root, 'android');
if (!existsSync(android)) fail('android/ does not exist yet. Run "npm run setup" first.');

const release = /release/i.test(task);
if (release && !existsSync(join(android, 'keystore.properties'))) {
  console.warn('\nWARNING: android/keystore.properties not found - the release build will be UNSIGNED.');
  console.warn('See README.md, section "Android signed release".\n');
}

const wrapper = process.platform === 'win32' ? 'gradlew.bat' : './gradlew';
if (!run(`${wrapper} ${task}`, { cwd: android })) fail(`Gradle task "${task}" failed.`);

const outputs = {
  assembleDebug: 'android/app/build/outputs/apk/debug/app-debug.apk',
  assembleRelease: 'android/app/build/outputs/apk/release/  (app-release.apk, or app-release-unsigned.apk without a keystore)',
  bundleRelease: 'android/app/build/outputs/bundle/release/app-release.aab',
};
if (outputs[task]) console.log(`\nOutput: ${outputs[task]}`);
