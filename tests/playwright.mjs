import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Playwright for the browser lanes: the repository's node_modules (bun add
// --no-save playwright), else npm's global packages, else bun's; none: a
// message saying how to install it, not a stack of require's paths.
// `node tests/playwright.mjs` only checks, so a lane can fail before it
// builds anything.
const require = createRequire(import.meta.url);

function npmRoot() {
	const r = spawnSync(process.platform === 'win32' ? 'npm.cmd' : 'npm', ['root', '-g'], { encoding: 'utf8', shell: process.platform === 'win32' });
	return r.status === 0 ? r.stdout.trim() : null;
}

export function playwright() {
	const places = ['playwright', path.join(process.execPath, '../../lib/node_modules/playwright')];
	const npm = npmRoot();
	if (npm) places.push(path.join(npm, 'playwright'));
	places.push(path.join(process.env.BUN_INSTALL ?? path.join(os.homedir(), '.bun'), 'install/global/node_modules/playwright'));
	for (const p of places) {
		try {
			return require(p);
		} catch (e) {
			if (e.code !== 'MODULE_NOT_FOUND') throw e;
		}
	}
	console.error('playwright: not in node_modules, npm\'s or bun\'s global packages: bun add --no-save playwright@1.56.1 && bunx playwright install chromium');
	process.exit(1);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) playwright();
