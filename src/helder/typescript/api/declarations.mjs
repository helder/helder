// Writes helder's TypeScript declaration files from its Haxe types
// (helder.typescript.api.Declarations): src/helder/view/index.d.ts and the
// others its modules' declaration classes name. Every TypeScript build writes
// helder's when they are stale (helder.typescript.Generator); this writes them
// at once, or checks them. `--check`: writes nothing, fails when one differs
// (CI's declarations lane runs it). A program's own modules: their
// declaration classes and class paths given.
//
//   node src/helder/typescript/api/declarations.mjs [--check] [--cp dir]... [pack.Module]...
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath} from 'node:url';

const src = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const built = spawnSync(process.execPath, [path.join(src, 'helder/compiler/build.mjs'), '--quiet'], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit']});
if (built.status !== 0) process.exit(1);
const r = spawnSync(built.stdout.trim(), ['--declarations', ...process.argv.slice(2)], {stdio: 'inherit', env: {...process.env, HELDER_SRC: src}});
process.exit(r.status ?? 1);
