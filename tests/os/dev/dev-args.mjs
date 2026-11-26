// helder dev's arguments under the dev host (src/helder/dev; the test lane
// dev-host): the host (helder.dev.DevHost) run as `helder dev <entry> -- <args>`
// runs it, `host <library> <args>`, with two builds of
// tests/os/dev/DevArgsCheck.hx (no window), the first handing over to the
// second: each build's Sys.args() is exactly <args>.
//   node tests/os/dev/dev-args.mjs <compiler> <work dir>
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const [compilerArg, workArg] = process.argv.slice(2);
const compiler = path.resolve(compilerArg ?? 'node_modules/.bin/haxe');
const work = path.resolve(workArg ?? fs.mkdtempSync(path.join(os.tmpdir(), 'helder-dev-args-')));
const win = process.platform === 'win32', mac = process.platform === 'darwin';
const ext = win ? '.dll' : mac ? '.dylib' : '.so';

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });
const std = path.join(path.dirname(compiler), 'std');
const haxe = (args) => {
	const r = spawnSync(compiler, [...args, ...(process.platform === 'linux' ? ['-D', 'hxmc.libc=glibc'] : []),
		...(fs.existsSync(std) ? ['-cp', std] : [])], { cwd: repo, encoding: 'utf8' });
	if (r.status !== 0) throw new Error('the build failed: ' + args.join(' ') + '\n' + (r.stdout + r.stderr).slice(-3000));
};
const host = path.join(work, 'host' + (win ? '.exe' : ''));
haxe(['-D', 'hxmc.markup-braces', '-cp', 'src', '-main', 'helder.dev.DevHost', '--custom-target', 'hxmc=' + host]);
// (Windows: each DLL at a base of its own, as helder dev gives them)
const libs = [1, 2].map((v) => {
	const lib = path.join(work, `DevArgs${v}${ext}`);
	haxe(['-cp', 'src', '-cp', 'tests/os/dev', '-main', 'DevArgsCheck', '-D', 'devargs_version=' + v, '-D', 'hxmc.dev',
		'-D', 'hxmc.shared', '-D', 'hxmc.dev-host', '-D', 'hxmc.exports=hxmc_dev_run,hxmc_dev_state',
		...(win ? ['-D', 'hxmc.dll-base=0x' + (0x10000000 + v * 0x20000000).toString(16)] : []),
		'helder.dev.Hosted', '--custom-target', 'hxmc=' + lib]);
	return lib;
});

const args = ['project', '--agent', 'two words', 'ü'];
const r = spawnSync(host, [libs[0], ...args], { encoding: 'utf8', timeout: 60000,
	env: { ...process.env, HXMC_DEV_NEXT: libs[1] } });
const out = (r.stdout + r.stderr).split(/\r?\n/).filter((l) => l);
for (const l of out) console.log('  | ' + l);
const want = [1, 2].map((v) => `DevArgsCheck: v${v} ${args.join('|')}`);
const ok = r.status === 0 && want.every((w) => out.includes(w));
console.log(ok ? 'dev-args: ok' : 'dev-args: FAIL, wanted ' + want.join(' / '));
process.exit(ok ? 0 : 1);
