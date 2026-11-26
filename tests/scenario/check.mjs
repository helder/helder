// Scenarios end to end (bun run test scenarios): the studio run headless on
// a copy of tests/scenario/fixtures/pong, each scenario's still snapped over
// MCP (run.snap) against the story that poses the same moment, pixel for
// pixel; then timed: the stills of the stories alone, of the scenarios
// alone (cold: built; again: from frames.hframes), the cache fresh after a
// live literal's patch, the clock fixture's screens deterministic (built
// twice, the same beside other neighbours, its zones and locales apart), the
// weather app's request answered by its fixtures (a request none matches
// failing its screen), the habits app's steps reaching its boot's pixels
// (a broken step failing its screen), and the
// screens' program's memory with 1 and 6 scenarios (bin/scenario/results.md).
//
//   node tests/scenario/check.mjs <helder> <out>
import {spawn, execFileSync} from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import zlib from 'node:zlib'

const [helder, out] = process.argv.slice(2)
const fixture = 'tests/scenario/fixtures/pong'
const pairs = ['Rally', 'Point scored', 'You win', 'You lose', 'Serve']
fs.rmSync(out, {recursive: true, force: true})
fs.mkdirSync(out, {recursive: true})

// (a copy of pong, without the files given, a repository of its own; its
// frames none: kept at the package's root, bin/studio/<name>, not the copy's)
function copy(name, without = [], from = fixture) {
  const base = path.basename(from) + '-' + name
  const dir = path.resolve(out, base)
  fs.rmSync(path.resolve('bin/studio', base), {recursive: true, force: true})
  fs.cpSync(from, dir, {recursive: true})
  for (const f of without) fs.rmSync(path.join(dir, f))
  execFileSync('git', ['init', '-q', '-b', 'studio', dir])
  return dir
}

let port = 47400
// (the screens' program's resident memory, MB: bin/studio/<name>/screens-n)
function rss(dir) {
  const ps = execFileSync('ps', ['-axo', 'rss=,command=']).toString().split('\n').find(l => l.includes(`/bin/studio/${path.basename(dir)}/screens`))
  return ps ? Number(ps.trim().split(/\s+/)[0]) / 1024 : NaN
}
// the studio on dir until f is done with it: f(call, log), call an MCP tool
async function studio(dir, f) {
  const p = port++, log = path.join(dir, '..', path.basename(dir) + '.log')
  const script = path.join(out, 'script.json')
  fs.writeFileSync(script, JSON.stringify({events: [{t: 100000, type: 'mark', name: 'end'}]}))
  const child = spawn(helder, ['run', '--headless', 'apps/studio', '--script', script, '--size', '1180x740', '--snap', path.join(out, 'end.png'), '--at', 'mark:end',
    '--', dir, '--mcp-port', String(p)], {env: {...process.env, HELDER_BACKGROUND: '1'}, detached: true})
  let text = ''
  for (const s of [child.stdout, child.stderr]) s.on('data', d => { text += d; fs.appendFileSync(log, d) })
  const wait = async (re, s = 300) => {
    for (let i = 0; i < s * 10; i++) {
      const m = text.match(re)
      if (m) return m
      await new Promise(r => setTimeout(r, 100))
    }
    throw new Error(`${dir}: no ${re} in ${s} s (${log})`)
  }
  const url = `http://127.0.0.1:${p}/mcp`
  let session = null, id = 0
  async function rpc(method, params) {
    const r = await fetch(url, {method: 'POST', headers: {'content-type': 'application/json', accept: 'application/json, text/event-stream', ...(session ? {'mcp-session-id': session} : {})},
      body: JSON.stringify({jsonrpc: '2.0', id: ++id, method, params})})
    session ??= r.headers.get('mcp-session-id')
    const t = await r.text()
    return JSON.parse(t.startsWith('{') ? t : t.split('\n').find(l => l.startsWith('data:')).slice(5))
  }
  const call = async (name, args) => {
    if (!session) await rpc('initialize', {protocolVersion: '2025-06-18', capabilities: {}, clientInfo: {name: 'check', version: '1'}})
    return (await rpc('tools/call', {name, arguments: args})).result
  }
  try {
    return await f(call, wait)
  } finally {
    try { process.kill(-child.pid) } catch {}
  }
}

// (a PNG's pixels: RGB(A), 8 bits, not interlaced)
function decode(b) {
  let p = 8, w, h, type, idat = []
  while (p < b.length) {
    const n = b.readUInt32BE(p), t = b.toString('ascii', p + 4, p + 8), d = b.subarray(p + 8, p + 8 + n)
    if (t === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); type = d[9] }
    if (t === 'IDAT') idat.push(d)
    p += 12 + n
  }
  const bpp = type === 6 ? 4 : 3, raw = zlib.inflateSync(Buffer.concat(idat)), px = Buffer.alloc(w * h * bpp), s = w * bpp
  for (let y = 0; y < h; y++) {
    const f = raw[y * (s + 1)]
    for (let x = 0; x < s; x++) {
      const v = raw[y * (s + 1) + 1 + x], a = x >= bpp ? px[y * s + x - bpp] : 0, u = y > 0 ? px[(y - 1) * s + x] : 0, c = x >= bpp && y > 0 ? px[(y - 1) * s + x - bpp] : 0
      const q = a + u - c, pa = Math.abs(q - a), pb = Math.abs(q - u), pc = Math.abs(q - c)
      px[y * s + x] = (v + [0, a, u, (a + u) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? u : c][f]) & 255
    }
  }
  return {w, h, bpp, px}
}

function differ(a, b) {
  if (a.w !== b.w || a.h !== b.h) return a.w * a.h
  let n = 0
  for (let i = 0; i < a.w * a.h; i++)
    for (let k = 0; k < 3; k++) if (a.px[i * a.bpp + k] !== b.px[i * b.bpp + k]) { n++; break }
  return n
}

const snap = async (call, screen) => decode(Buffer.from((await call('run.snap', {screen})).content.find(c => c.type === 'image').data, 'base64'))
const ms = (re, text) => Number(text.match(re)?.[1] ?? NaN)
const results = []
let failed = 0

// 1. a scenario's still is the story's that poses its moment
await studio(copy('both'), async (call, wait) => {
  await wait(/Pong\/In motion's loop kept/)
  for (const m of pairs) {
    const d = differ(await snap(call, `Pong/${m}`), await snap(call, `Court/${m}`))
    console.log(`Pong/${m} against Court/${m}: ${d} pixels differ`)
    if (d > 0) failed++
  }
})

// 2. stills timed: stories alone, scenarios alone; cold (built) and from the frame cache
for (const [name, without] of [['stories', ['pong.scenario.tsx']], ['scenarios', ['pong.story.tsx']]]) {
  const dir = copy(name, without)
  for (const pass of ['cold', 'cached']) {
    const r = await studio(dir, async (call, wait) => {
      const m = await wait(pass === 'cold' ? /all (\d+) screens shown (\d+) ms after opening \S+, (\d+) ms after the screens' program started/ : /all (\d+) screens shown (\d+) ms after opening/)
      // (the stills written to frames.hframes a moment after they settle)
      if (pass === 'cold') await wait(/In motion's loop kept/, 120)
      await new Promise(r => setTimeout(r, 3000))
      return {screens: +m[1], open: +m[2], program: m[3] ? +m[3] : null, rss: pass === 'cold' ? rss(dir) : NaN}
    })
    results.push({name, pass, ...r})
    console.log(name, pass, JSON.stringify(r))
  }
}

// 3. the frame cache after a live literal's patch: every still fresh when reopened
const cache = copy('cache')
await studio(cache, async (call, wait) => {
  await wait(/In motion's loop kept/)
  const r = await call('project.patch', {path: 'pong.tsx', edits: [{old: 'fontSize={13} color="#8a93a8">Press P', new: 'fontSize={14} color="#8a93a8">Press P'}]})
  console.log('literal patch:', r.content.map(c => c.text).join(' ').slice(0, 200))
  await new Promise(r => setTimeout(r, 5000))
})
const reopened = await studio(cache, async (call, wait) => (await wait(/(\d+) stills \((\d+) of files changed since/))[2])
console.log(`reopened after a literal patch: ${reopened} stale`)
if (+reopened > 0) failed++

// 5. determinism (phase 2): the clock fixture (its zone's date, its locale's
// formats, Math.random, a timer on its clock) the same pixels built twice,
// a screen the same beside other neighbours, and its places apart
const places = ['Brussels', 'Delhi', 'Plain']
async function stills(dir, names) {
  return studio(dir, async (call, wait) => {
    await wait(/all (\d+) screens shown/)
    const got = {}
    for (const n of names) {
      const r = await call('run.snap', {screen: `Clock/${n}`})
      const png = Buffer.from(r.content.find(c => c.type === 'image').data, 'base64')
      fs.writeFileSync(path.join(out, `${path.basename(dir)}-${n}.png`), png)
      got[n] = decode(png)
    }
    return got
  })
}
const clockFixture = 'tests/scenario/fixtures/clock'
const first = await stills(copy('first', [], clockFixture), places)
const second = await stills(copy('second', [], clockFixture), places)
// (beside other neighbours: three screens of one size as before, the canvas'
// zoom the same, Delhi's two neighbours other zones, locales, seeds and times)
const others = copy('others', [], clockFixture)
fs.writeFileSync(path.join(others, 'app.scenario.tsx'), fs.readFileSync(path.join(others, 'app.scenario.tsx'), 'utf8')
  .replace('zone: "+01:00", locale: "nl-BE", seed: 3, play: 3', 'zone: "-08:00", locale: "en-US", seed: 9, play: 5')
  .replace('time: "2026-11-26T09:00", play: 3 })', 'time: "2027-01-01T00:00", seed: 11, play: 1 })'))
const besideOthers = await stills(others, ['Delhi'])
for (const n of places) {
  const d = differ(first[n], second[n])
  console.log(`Clock/${n} built twice: ${d} pixels differ`)
  if (d > 0) failed++
}
const besides = differ(first.Delhi, besideOthers.Delhi)
console.log(`Clock/Delhi beside other neighbours (their zones, locales, seeds and timers): ${besides} pixels differ`)
if (besides > 0) failed++
const apart = differ(first.Brussels, first.Delhi)
console.log(`Clock/Brussels against Clock/Delhi: ${apart} pixels differ (their zones and locales)`)
if (apart === 0) failed++

// 6. http fixtures (phase 2): the weather app's request answered by its
// scenario's fixture, a file's JSON and a 503, the same pixels as the
// stories that pose those answers; a request none matches fails its screen,
// named in the studio's log
const weather = 'tests/scenario/fixtures/weather'
const served = await studio(copy('served', [], weather), async (call, wait) => {
  await wait(/all (\d+) screens shown/)
  await new Promise(r => setTimeout(r, 2000))
  const diffs = {}
  async function saved(name) {
    const r = await call('run.snap', {screen: name})
    const png = Buffer.from(r.content.find(c => c.type === 'image').data, 'base64')
    fs.writeFileSync(path.join(out, `weather-${name.replace('/', '-')}.png`), png)
    return decode(png)
  }
  for (const [scene, story] of [['Weather/Ghent', 'Forecast/Ghent'], ['Weather/Offline', 'Forecast/Offline']])
    diffs[scene] = differ(await saved(scene), await saved(story))
  return diffs
})
for (const [scene, d] of Object.entries(served)) {
  console.log(`${scene} (its http fixture) against its story: ${d} pixels differ`)
  if (d > 0) failed++
}
const unmatched = copy('unmatched', [], weather)
fs.writeFileSync(path.join(unmatched, 'app.scenario.tsx'), fs.readFileSync(path.join(unmatched, 'app.scenario.tsx'), 'utf8').replace('"api.open-meteo.com/v1/forecast*"', '"api.example.com/*"'))
const named = await studio(unmatched, async (call, wait) => (await wait(/Weather\/Ghent crashed: ([^\n]*)/, 120))[1])
console.log(`a request no fixture matches: Weather/Ghent crashed: ${named}`)
if (!/no http fixture for GET https:\/\/api\.open-meteo\.com\/v1\/forecast/.test(named)) failed++

// 7. steps (phase 2): the habits app's moments reached by hand (taps and
// typing after boot) the same pixels as boot writing them; a step that no
// longer resolves fails its screen, its near misses named
const habits = 'tests/scenario/fixtures/habits'
const byHand = await studio(copy('steps', [], habits), async (call, wait) => {
  await wait(/all (\d+) screens shown/)
  const diffs = {}
  async function saved(name) {
    const r = await call('run.snap', {screen: name})
    const png = Buffer.from(r.content.find(c => c.type === 'image').data, 'base64')
    fs.writeFileSync(path.join(out, `habits-${name.replace(/[/, ]+/g, '-')}.png`), png)
    return decode(png)
  }
  for (const name of ['Habits/All done', 'Habits/Added'])
    diffs[name] = differ(await saved(`${name}, by hand`), await saved(name))
  return diffs
})
for (const [name, d] of Object.entries(byHand)) {
  console.log(`${name}, by hand (its steps) against boot alone: ${d} pixels differ`)
  if (d > 0) failed++
}
const broken = copy('broken', [], habits)
fs.writeFileSync(path.join(broken, 'app.scenario.tsx'), fs.readFileSync(path.join(broken, 'app.scenario.tsx'), 'utf8').replace('tap("Add")', 'tap("Ad")'))
const stepped = await studio(broken, async (call, wait) => (await wait(/Habits\/Added, by hand crashed: ([^\n]*)/, 120))[1])
console.log(`a step that no longer resolves: Habits/Added, by hand crashed: ${stepped}`)
if (!/step 2: no "Ad" \(near: button "Add"/.test(stepped)) failed++

// 4. memory per scenario screen: 1 scenario against 6
const one = copy('one', ['pong.story.tsx'])
fs.writeFileSync(path.join(one, 'pong.scenario.tsx'), fs.readFileSync(path.join(one, 'pong.scenario.tsx'), 'utf8').split('\n').filter(l => !l.startsWith('export') || l.includes('"Pong/Rally"')).join('\n'))
const single = await studio(one, async (call, wait) => {
  await wait(/all (\d+) screens shown/)
  await new Promise(r => setTimeout(r, 3000))
  return rss(one)
})
const six = results.find(r => r.name === 'scenarios' && r.pass === 'cold')?.rss
const md = ['# Scenarios against stories: pong', '', '| screens | pass | n | shown after opening (ms) | after the program started (ms) | program RSS (MB) |', '|---|---|---|---|---|---|']
  .concat(results.map(r => `| ${r.name} | ${r.pass} | ${r.screens} | ${r.open} | ${r.program ?? '—'} | ${isNaN(r.rss) ? '—' : r.rss.toFixed(1)} |`))
  .concat(['', `Memory a scenario screen: (${six?.toFixed(1)} − ${single.toFixed(1)}) / 5 = ${((six - single) / 5).toFixed(2)} MB`])
fs.writeFileSync(path.join(out, 'results.md'), md.join('\n') + '\n')
console.log(md.join('\n'))
if (failed > 0) {
  console.log(`${failed} check(s) failed`)
  process.exit(1)
}
