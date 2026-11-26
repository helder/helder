import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import {spawnSync} from 'node:child_process'
import {Random, seedOf} from './Random.mjs'
import {Generator} from './Generator.mjs'
import {Server} from './Server.mjs'
import {Runner} from './Runner.mjs'
import {Shrinker} from './Shrinker.mjs'
import {emit} from './Program.mjs'

// A differential fuzzer of helder's TypeScript (tests/typescript/fuzz,
// README.md there): random well-typed programs run by node and by helder's
// compiler, natively and (a sample) as wasm32-wasi; a difference, a crash,
// a hang or a refused program is shrunk to a case of its own.
//
// node tests/typescript/fuzz/fuzz.mjs [--seconds n | --programs n]
//   [--seed n] [--cases n] [--jobs n] [--wasm every] [--lies] [--out dir]
//   [--store dir] [--no-shrink] [--write] [--known]
// The seed is HELDER_PROPERTY_SEED's (a number, or random) unless --seed
// says; program i of a seed is the same everywhere (--program i alone
// replays it). Findings are kept in <out>/properties (replayed first on the
// next run, removed once they pass); --write puts each shrunk one in
// tests/typescript/cases (or diverge/, the lies').

const args = process.argv.slice(2)
const flag = name => args.includes(name)
const option = (name, fallback) => {
  const i = args.indexOf(name)
  return i < 0 ? fallback : args[i + 1]
}
const seed = seedOf(option('--seed', process.env.HELDER_PROPERTY_SEED ?? '0'))
const seconds = Number(option('--seconds', 0))
const programs = Number(option('--programs', seconds ? Infinity : 20))
const only = option('--program', null)
const perProgram = Number(option('--cases', 40))
const jobs = Number(option('--jobs', 2))
const wasmEvery = Number(option('--wasm', 5))
const lies = flag('--lies')
const out = path.resolve(option('--out', 'bin/typescript-fuzz'))
const shrink = !flag('--no-shrink')
const write = flag('--write')
const known = flag('--known')
const root = process.cwd()

const built = spawnSync(process.execPath, ['src/helder/compiler/build.mjs', '--quiet'], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit']})
if (built.status !== 0) process.exit(1)
const compiler = built.stdout.trim()
const store = path.resolve(option('--store', path.join(out, 'properties')))
fs.mkdirSync(store, {recursive: true})

const t0 = Date.now()
const stats = {programs: 0, cases: 0, wasm: 0, typing: 0, findings: [], replayed: 0}
const workers = await Promise.all(Array.from({length: jobs}, async (_, k) => {
  const server = await Server.start(compiler, root)
  const runner = new Runner(server, path.join(out, `w${k}`), {lies})
  return {server, runner}
}))
let next = only != null ? Number(only) : 0
const last = only != null ? Number(only) + 1 : programs
const done = () => next >= last || (seconds && Date.now() - t0 > seconds * 1000)

console.log(`typescript fuzz: seed ${seed}${lies ? ', lies' : ''}, ${perProgram} cases a program, ${jobs} servers${seconds ? `, ${seconds} s` : `, ${last - next} programs`} (HELDER_PROPERTY_SEED=${seed} replays it)`)
await replay(workers[0])
try {
  await Promise.all(workers.map(w => work(w)))
} finally {
  for (const w of workers) w.server.stop()
}
report()
process.exit(stats.findings.length ? 1 : 0)

async function work({runner}) {
  while (!done()) {
    const index = next++
    const g = new Generator(new Random(seed, index, lies ? 1 : 0), {lies, known})
    const cases = Array.from({length: perProgram}, (_, k) => g.case(k))
    const wasm = wasmEvery > 0 && index % wasmEvery === 0
    const name = `p${seed}-${index}`
    const result = await runner.run(cases, name, {wasm})
    stats.programs++
    stats.cases += cases.length
    if (wasm) stats.wasm++
    if (result.typing) {
      stats.typing++
      keep(result, 'generator')
      console.log(`${name}: not a program tsgo accepts (the generator's fault): ${firstLine(result.typing)}`)
      continue
    }
    const failed = cases.filter(c => !['ok', 'unreached'].includes(result.verdicts.get(c.id)))
    if (!failed.length) {
      clean(result)
      continue
    }
    keep(result, 'found')
    if (result.unplaced) {
      console.log(`${name}: compile, at no case's line: ${firstLine(result.messages)}`)
      await found(runner, cases, null, 'compile', {seed, index, wasm})
      continue
    }
    for (const c of failed.slice(0, 3)) {
      const kind = result.verdicts.get(c.id)
      console.log(`${name} c${c.id} (${c.family}): ${kind}${result.messages ? ' ' + firstLine(result.messages) : ''}`)
      await found(runner, cases, c, kind, {seed, index, wasm})
    }
  }
}

async function found(runner, cases, c, kind, origin) {
  let small = {cases: [c], kind}
  if (shrink) small = await new Shrinker(runner, {wasm: kind.startsWith('wasm'), log: m => console.log(`  ${m}`)}).shrink(cases, c, kind)
  // (as a plain program where that still fails: no harness, the values printed alone)
  const plain = emit(small.cases, {plain: true}).text
  const {text} = !lies && await runner.runText(plain, `plain-${process.pid}`, {wasm: small.kind.startsWith('wasm')}) ? {text: plain} : emit(small.cases)
  const hash = crypto.createHash('sha1').update(text).digest('hex').slice(0, 8)
  const finding = {kind: small.kind, family: c?.family ?? 'program', ...origin, case: c?.id ?? null, hash, lies}
  stats.findings.push(finding)
  const json = JSON.stringify({...finding, cases: small.cases.map(c => ({...c, features: [...c.features]}))}, null, 1)
  fs.writeFileSync(path.join(store, `typescript-${hash}.json`), json)
  const name = `fuzz-${hash}.ts`
  const target = write ? path.join(root, 'tests/typescript', lies && small.kind === 'mismatch' ? 'diverge' : 'cases', name) : path.join(out, 'found', name)
  fs.mkdirSync(path.dirname(target), {recursive: true})
  fs.writeFileSync(target, `// fuzz: seed ${origin.seed}, program ${origin.index}${c ? `, case ${c.id} (${c.family})` : ''}: ${small.kind}${small.whole ? ' (not shrunk)' : ''}\n${text}`)
  console.log(`  ${small.kind}: ${path.relative(root, target)} (${text.split('\n').length} lines)`)
}

// the findings kept by an earlier run, first: removed once they pass
async function replay({runner}) {
  for (const f of fs.readdirSync(store).filter(f => /^typescript-.*\.json$/.test(f))) {
    const kept = JSON.parse(fs.readFileSync(path.join(store, f), 'utf8'))
    if (kept.lies !== lies) continue
    const result = await runner.run(kept.cases, `kept-${kept.hash}`, {wasm: kept.kind.startsWith('wasm')})
    clean(result)
    stats.replayed++
    const bad = [...result.verdicts.values()].filter(v => !['ok', 'unreached'].includes(v))
    if (!bad.length && !result.typing) {
      console.log(`kept ${kept.hash} (${kept.kind}): passes now, removed`)
      fs.rmSync(path.join(store, f))
    } else {
      console.log(`kept ${kept.hash} (${kept.kind}): still ${bad[0] ?? 'refused'} (${path.relative(root, path.join(store, f))})`)
      stats.findings.push({...kept, cases: undefined, replayed: true})
    }
  }
}

function keep(result, why) {
  const dir = path.join(out, why)
  fs.mkdirSync(dir, {recursive: true})
  fs.copyFileSync(result.file, path.join(dir, path.basename(result.file)))
  const log = [`node: ${result.node.status}`, result.messages ?? '', result.typing ?? '']
  fs.writeFileSync(path.join(dir, path.basename(result.file, '.ts') + '.log'), log.join('\n'))
  clean(result)
}

function clean(result) {
  for (const f of [result.file, result.exe, result.exe + '.wasm']) fs.rmSync(f, {force: true})
}

function firstLine(text) {
  return text.trim().split('\n')[0].slice(0, 300)
}

function report() {
  const s = (Date.now() - t0) / 1000
  const t = workers.map(w => w.runner.times)
  const sum = k => Math.round(t.reduce((a, x) => a + x[k], 0) / 1000)
  console.log(`typescript fuzz: ${stats.programs} programs, ${stats.cases} cases (${stats.wasm} programs on wasm32-wasi) in ${Math.round(s)} s: ${Math.round(stats.cases / s * 60)} cases/minute; node ${sum('node')} s, compile ${sum('compile')} s, run ${sum('run')} s, wasm ${sum('wasm')} s${stats.typing ? `; ${stats.typing} programs the generator got wrong` : ''}`)
  for (const f of stats.findings) console.log(`  finding ${f.hash}: ${f.kind} (${f.family}, seed ${f.seed}, program ${f.index}${f.replayed ? ', kept' : ''})`)
  if (!stats.findings.length) console.log('  no findings')
}
