// helder's machine-wide job limit for node's scripts: Slots.hx's slots, the
// same directories and owner files (see there).
//
//   const release = take()          a slot, waiting for one; null: no limit
//   const release = await wait()    the same, without blocking the event loop
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import {spawnSync} from 'node:child_process'

export const HELD = 'HELDER_SLOT'

export function cache() {
  const env = process.env.HELDER_CACHE
  if (env) return env
  if (process.platform === 'win32') return path.join(process.env.LOCALAPPDATA ?? path.join(os.homedir(), 'AppData/Local'), 'helder')
  if (process.platform === 'darwin') return path.join(os.homedir(), 'Library/Caches/helder')
  return path.join(process.env.XDG_CACHE_HOME ?? path.join(os.homedir(), '.cache'), 'helder')
}

export function jobs() {
  const n = Number.parseInt(process.env.HELDER_JOBS ?? '')
  if (n >= 0) return n
  return Math.max(1, Math.floor(os.availableParallelism() / 4))
}

export function slots(dir = path.join(cache(), 'slots'), count = jobs()) {
  const off = () => count === 0 || process.env[HELD] === '1'
  const busy = () => fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => /^\d+$/.test(f)).length : 0

  function tryTake() {
    fs.mkdirSync(dir, {recursive: true})
    const token = String(random()), mine = path.join(dir, `.new-${process.pid}-${token}`)
    fs.mkdirSync(mine)
    fs.writeFileSync(path.join(mine, 'owner'), `${process.pid} ${Math.floor(Date.now() / 1000)} ${token}`)
    try {
      for (let pass = 0; pass < 2; pass++) {
        for (let n = 0; n < count; n++) {
          const slot = path.join(dir, String(n))
          if (rename(mine, slot)) return () => release(slot, token)
        }
        let freed = false
        for (let n = 0; n < count; n++) if (reclaim(path.join(dir, String(n)))) freed = true
        if (!freed) break
      }
    } finally {
      remove(mine)
    }
    return null
  }

  function reclaim(slot) {
    const o = owner(slot)
    if (o ? alive(o.pid, o.since) : !old(slot)) return false
    const away = path.join(dir, `.dead-${process.pid}-${random()}`)
    if (!rename(slot, away)) return false
    const now = owner(away)
    if (now?.token !== o?.token) {
      rename(away, slot)
      return false
    }
    remove(away)
    return true
  }

  function release(slot, token) {
    const o = owner(slot)
    if (!o || o.token !== token) return
    const away = path.join(dir, `.done-${token}`)
    if (rename(slot, away)) remove(away)
  }

  function take() {
    if (off()) return null
    let delay = 50
    for (let said = false; ; said = true) {
      const r = tryTake()
      if (r) return r
      if (!said) console.error(`waiting for a build slot (${busy()} busy)`)
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, delay)
      delay = Math.min(delay * 2, 1000)
    }
  }

  async function wait() {
    if (off()) return null
    let delay = 50
    for (let said = false; ; said = true) {
      const r = tryTake()
      if (r) return r
      if (!said) console.error(`waiting for a build slot (${busy()} busy)`)
      await new Promise(done => setTimeout(done, delay))
      delay = Math.min(delay * 2, 1000)
    }
  }

  return {dir, count, off, busy, tryTake, take, wait}
}

export const take = () => slots().take()
export const wait = () => slots().wait()

export function owner(slot) {
  try {
    const [p, t, token] = fs.readFileSync(path.join(slot, 'owner'), 'utf8').trim().split(' ')
    const pid = Number.parseInt(p), since = Number.parseFloat(t)
    return Number.isNaN(pid) || Number.isNaN(since) || !token ? null : {pid, since, token}
  } catch {
    return null
  }
}

// (Slots.hx's alive: running, and started before the slot was taken)
export function alive(pid, since) {
  try {
    const start = started(pid)
    return start !== null && start <= since + 2
  } catch {
    return true
  }
}

function started(pid) {
  if (process.platform === 'linux') {
    if (!fs.existsSync(`/proc/${pid}/stat`)) return null
    const s = fs.readFileSync(`/proc/${pid}/stat`, 'utf8'), f = s.slice(s.lastIndexOf(')') + 2).split(' ')
    const boot = /btime (\d+)/.exec(fs.readFileSync('/proc/stat', 'utf8'))
    if (!boot) throw new Error('no btime')
    return Number(boot[1]) + Number(f[19]) / 100
  }
  if (process.platform === 'win32') {
    const out = spawnSync('powershell', ['-NoProfile', '-Command',
      `$p = Get-Process -Id ${pid} -ErrorAction SilentlyContinue; if ($p) { ([DateTimeOffset]$p.StartTime).ToUnixTimeSeconds() }`], {encoding: 'utf8'})
    if (out.error) throw out.error
    return out.stdout.trim() === '' ? null : Number(out.stdout.trim())
  }
  const out = spawnSync('ps', ['-o', 'etime=', '-p', String(pid)], {encoding: 'utf8'})
  if (out.error) throw out.error
  const e = out.stdout.trim()
  if (e === '') return null
  const days = e.split('-')
  let secs = days.at(-1).split(':').reduce((a, p) => a * 60 + Number(p), 0)
  if (days.length > 1) secs += Number(days[0]) * 86400
  return Date.now() / 1000 - secs
}

// (no owner a minute on: not a slot of ours)
function old(slot) {
  try {
    return Date.now() - fs.statSync(slot).mtimeMs >= 60000
  } catch {
    return false
  }
}

function rename(from, to) {
  try {
    fs.renameSync(from, to)
    return true
  } catch {
    return false
  }
}

function remove(d) {
  fs.rmSync(d, {recursive: true, force: true})
}

function random() {
  return Math.floor(Math.random() * 0x7fffffff)
}
