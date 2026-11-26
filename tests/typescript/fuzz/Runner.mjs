import fs from 'node:fs'
import path from 'node:path'
import {spawn} from 'node:child_process'
import {emit} from './Program.mjs'

// One program of cases run by node (types stripped: the reference) and by
// helder's compiler (natively, or as wasm32-wasi under node), each case's
// trace compared. A case's verdict: ok, or what went wrong (mismatch,
// crash, hang, compile: helder refused what tsgo accepted, typing: tsgo
// refused it, the generator's fault).
export class Runner {
  constructor(server, dir, options = {}) {
    this.server = server
    this.dir = dir
    this.timeout = options.timeout ?? 30000
    this.lies = options.lies ?? false
    this.times = {node: 0, compile: 0, run: 0, wasm: 0}
    fs.mkdirSync(dir, {recursive: true})
  }

  async run(cases, name, {wasm = false} = {}) {
    const {text, ranges, lies} = emit(cases)
    const file = path.join(this.dir, `${name}.ts`)
    fs.writeFileSync(file, text)
    const exe = path.join(this.dir, name)
    let t = Date.now()
    const [node, built] = await Promise.all([
      execute(process.execPath, ['--no-warnings', file], this.timeout).then(r => (this.times.node += Date.now() - t, r)),
      this.server.build(file, exe).then(r => (this.times.compile += Date.now() - t, r))
    ])
    const result = {file, exe, text, ranges, lies, node, built, verdicts: new Map()}
    if (node.status !== 0 || node.signal) {
      result.typing = `node: ${node.status ?? node.signal}\n${node.stderr.slice(0, 2000)}`
      return result
    }
    if (!built.ok) {
      const typing = /\bTS\d+:/.test(built.messages) && !/TSHX/.test(built.messages)
      for (const c of cases) result.verdicts.set(c.id, 'unreached')
      const lines = [...built.messages.matchAll(/\.ts:(\d+):/g)].map(m => Number(m[1]))
      const blamed = cases.filter(c => ranges.get(c.id).some(([a, b]) => lines.some(l => l >= a && l <= b)))
      for (const c of blamed.length ? blamed : cases) result.verdicts.set(c.id, typing ? 'typing' : 'compile')
      // (an error at no line of a case: the program's as a whole)
      result.unplaced = !blamed.length
      if (typing) result.typing = built.messages
      result.messages = built.messages
      return result
    }
    t = Date.now()
    const native = await execute(exe, [], this.timeout)
    this.times.run += Date.now() - t
    result.native = native
    this.judge(cases, result, native)
    if (wasm && [...result.verdicts.values()].every(v => v === 'ok')) {
      t = Date.now()
      const out = exe + '.wasm'
      const w = await this.server.build(file, out, 'wasm32-wasi')
      if (!w.ok) {
        for (const c of cases) result.verdicts.set(c.id, 'compile')
        result.messages = 'wasm32-wasi: ' + w.messages
      } else {
        const ran = await execute(process.execPath, [path.resolve('tests/typescript/run-wasi.cjs'), out], this.timeout)
        result.wasm = ran
        this.judge(cases, result, ran, 'wasm ')
      }
      this.times.wasm += Date.now() - t
    }
    return result
  }

  // a program as it is (a regression test's): whether helder's run differs from node's
  async runText(text, name, {wasm = false} = {}) {
    const file = path.join(this.dir, `${name}.ts`), exe = path.join(this.dir, name)
    fs.writeFileSync(file, text)
    const target = wasm ? 'wasm32-wasi' : undefined, out = wasm ? exe + '.wasm' : exe
    const [node, built] = await Promise.all([execute(process.execPath, ['--no-warnings', file], this.timeout), this.server.build(file, out, target)])
    const ran = !built.ok ? null : wasm ? await execute(process.execPath, [path.resolve('tests/typescript/run-wasi.cjs'), out], this.timeout) : await execute(exe, [], this.timeout)
    for (const f of [file, exe, exe + '.wasm']) fs.rmSync(f, {force: true})
    if (node.status !== 0) return false
    return !ran || ran.hung || ran.status !== node.status || ran.stdout !== node.stdout
  }

  // (a case the run never reached, past another's crash, is not judged)
  judge(cases, result, run, prefix = '') {
    const want = traces(result.node.stdout), got = traces(run.stdout)
    const last = [...got.keys()].pop()
    const abnormal = run.hung ? 'hang' : run.signal || run.status !== result.node.status ? 'crash' : null
    for (const c of cases) {
      const name = `c${c.id}`, a = want.get(name) ?? [], b = got.get(name)
      let verdict
      if (name === last && abnormal) verdict = abnormal
      else if (!b) verdict = abnormal ? 'unreached' : 'mismatch'
      else verdict = same(a, b, this.lies ? result.lies.get(c.id) : null) ? 'ok' : 'mismatch'
      const before = result.verdicts.get(c.id)
      if (before === undefined || before === 'ok' || before === 'unreached')
        result.verdicts.set(c.id, verdict === 'ok' || verdict === 'unreached' ? verdict : prefix + verdict)
    }
  }
}

// a case's lines: same, or (lies) node's up to the lie, then helder's stop at it
function same(want, got, lie) {
  if (want.length === got.length && want.every((l, i) => l === got[i])) return true
  if (lie == null) return false
  const stop = got.findIndex(l => / TSHX100 /.test(l))
  if (stop !== got.length - 1 || !got[stop].endsWith(` TSHX100 L${lie}`)) return false
  return got.slice(0, stop).every((l, i) => l === want[i])
}

export function traces(stdout) {
  const out = new Map()
  let current = null
  for (const line of stdout.split('\n')) {
    const start = /^# (c\d+)$/.exec(line)
    if (start) out.set(current = start[1], [])
    else if (current && line !== '') out.get(current).push(line)
  }
  return out
}

export function execute(cmd, args, timeout) {
  return new Promise(resolve => {
    const child = spawn(cmd, args, {stdio: ['ignore', 'pipe', 'pipe'], env: {...process.env, HELDER_BACKGROUND: '1'}})
    let stdout = '', stderr = '', hung = false
    child.stdout.on('data', d => {if (stdout.length < 4e6) stdout += d})
    child.stderr.on('data', d => {if (stderr.length < 1e5) stderr += d})
    const timer = setTimeout(() => {hung = true; child.kill('SIGKILL')}, timeout)
    child.on('error', error => {clearTimeout(timer); resolve({status: null, signal: null, stdout, stderr: String(error), hung})})
    child.on('close', (status, signal) => {clearTimeout(timer); resolve({status, signal, stdout, stderr, hung})})
  })
}
