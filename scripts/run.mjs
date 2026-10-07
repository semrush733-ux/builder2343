// Small helpers shared by the project scripts (works on Windows, macOS and Linux).
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = join(dirname(fileURLToPath(import.meta.url)), '..');

/** Runs a command line, streaming its output. Returns true on success. */
export function run(commandLine, options = {}) {
  console.log(`\n> ${commandLine}`);
  const result = spawnSync(commandLine, {
    cwd: options.cwd || root,
    stdio: 'inherit',
    shell: true,
    env: process.env,
  });
  return result.status === 0;
}

export function fail(message) {
  console.error(`\nERROR: ${message}`);
  process.exit(1);
}
