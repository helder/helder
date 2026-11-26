// The studio ends with its launcher, however the launcher ends: `helder
// studio`, then `helder dev apps/studio`, each on a copy of pong
// (tests/scenario/fixtures/pong) with the scripted ACP agent and a play
// window (--play), the previews' host woken over MCP (run.snap); once the
// studio, its host, Play's helder dev and its program and the agent run,
// the launcher killed with SIGKILL; every process of its tree (by pid, this
// run's alone) gone within 20 s, else the lane fails and what was left is
// killed.
//
//   node tests/studio/orphans.mjs <helder>
import { spawn, execFileSync } from 'node:child_process'
import fs from 'node:fs'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'

const [helder] = process.argv.slice(2)
if (!helder) throw new Error('usage: node tests/studio/orphans.mjs <helder>')
const sleep = s => new Promise(r => setTimeout(r, s * 1000))
function alive(pid) {
  try { process.kill(pid, 0); return true } catch { return false }
}

async function check(name, launch) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'helder-orphans-'))
  fs.cpSync('tests/scenario/fixtures/pong', dir, { recursive: true })
  const port = await new Promise(done => {
    const s = net.createServer().listen(0, '127.0.0.1', () => {
      const p = s.address().port
      s.close(() => done(p))
    })
  })
  const agent = `${process.execPath} ${path.resolve('tests/studio/acp-agent.mjs')}`
  const log = fs.openSync(path.join(dir, 'studio.log'), 'w')
  const launcher = spawn(helder, launch(dir, ['--agent', agent, '--mcp-port', String(port), '--play', 'Pong/Rally']), {
    // (Play's helder dev: this one, as `helder studio` sets it; `helder dev apps/studio` is told so)
    env: { ...process.env, HELDER_BACKGROUND: '1', HELDER_CLI: path.resolve(helder) },
    stdio: ['ignore', log, log]
  })

  // (the launcher's tree: pid, parent, command, from ps)
  function tree() {
    const rows = execFileSync('ps', ['-A', '-o', 'pid=,ppid=,command=']).toString().split('\n')
      .map(l => l.trim().match(/^(\d+)\s+(\d+)\s+(.*)$/)).filter(Boolean).map(m => ({ pid: +m[1], ppid: +m[2], command: m[3] }))
    const out = [], seen = new Set([launcher.pid])
    for (let more = true; more;) {
      more = false
      for (const r of rows) if (seen.has(r.ppid) && !seen.has(r.pid)) { seen.add(r.pid); out.push(r); more = true }
    }
    return out
  }
  async function mcp(method, params) {
    const r = await fetch(`http://127.0.0.1:${port}/mcp`, {
      method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params })
    })
    return r.text()
  }

  let failed = null, kept = []
  try {
    // (the studio up: its MCP answers)
    for (let t = 0; ; t++) {
      if (t > 420) throw new Error('the studio did not start (studio.log)')
      if (await mcp('tools/list', {}).catch(() => null)) break
      await sleep(1)
    }
    // (its host woken: a screen's frame asked for, the program built and run)
    mcp('tools/call', { name: 'run.snap', arguments: { screen: 'Pong/Serve' } }).catch(() => {})
    const wanted = {
      studio: r => r.command.includes(dir) && !/ dev |screens-|\.helder-play|tsc |compiler/.test(r.command),
      host: r => /\/screens-\d+/.test(r.command),
      play: r => / dev .*\.helder-play\.tsx/.test(r.command),
      program: r => /\.helder-play( |$)/.test(r.command) && !/ dev /.test(r.command),
      agent: r => r.command.includes('acp-agent.mjs')
    }
    for (let t = 0; ; t++) {
      kept = tree()
      const missing = Object.keys(wanted).filter(k => !kept.some(wanted[k]))
      if (missing.length === 0) break
      if (t > 420) throw new Error(`not all running after 420 s: ${missing.join(', ')}`)
      await sleep(1)
    }
    console.log(`studio-orphans: ${name}: ${kept.length} processes under the launcher (${launcher.pid})`)
    for (const r of kept) console.log(`  ${r.pid} ${r.command.slice(0, 120)}`)
    process.kill(launcher.pid, 'SIGKILL')
    console.log(`studio-orphans: ${name}: the launcher killed (SIGKILL)`)
    // (a shared daemon a build starts, helder's build server, outlives builds by design)
    const ours = kept.filter(r => !r.command.includes('__build-server'))
    for (let t = 0; t < 40 && ours.some(r => alive(r.pid)); t++) await sleep(0.5)
    const left = ours.filter(r => alive(r.pid))
    if (left.length > 0) failed = 'left running: ' + left.map(r => `${r.pid} ${r.command.slice(0, 100)}`).join('; ')
    else console.log(`studio-orphans: ${name}: ok: all ${ours.length} gone`)
  } catch (e) {
    failed = e.message
  } finally {
    try { process.kill(launcher.pid, 'SIGKILL') } catch {}
    for (const r of kept) if (alive(r.pid)) try { process.kill(r.pid, 'SIGKILL') } catch {}
  }
  if (failed) {
    console.log(`studio-orphans: ${name}: FAIL: ${failed}`)
    console.log(fs.readFileSync(path.join(dir, 'studio.log'), 'utf8').split('\n').filter(l => /^studio:|error|failed/.test(l)).slice(-20).join('\n'))
    return false
  }
  fs.rmSync(dir, { recursive: true, force: true })
  return true
}

const a = await check('helder studio', (dir, args) => ['studio', dir, '--', ...args])
const b = await check('helder dev apps/studio', (dir, args) => ['dev', 'apps/studio', '--', dir, ...args])
if (!a || !b) process.exit(1)
