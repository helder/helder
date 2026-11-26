// The viewer's scenarios in the studio (bun run test viewer-scenarios): the
// studio run headless on a copy of apps/viewer, every scenario's still
// snapped over MCP (run.snap) and checked drawn (not one colour), each
// beside the story that poses the same moment (pixels that differ, both
// written as PNGs); then timed: the stills after the screens' program
// started (cold: built; again: from frames.hframes), and the screens'
// program's memory with every screen against one scenario alone
// (bin/scenario-viewer/results.md).
//
//   node tests/scenario/viewer.mjs <helder> <out>
import {spawn, execFileSync} from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import zlib from 'node:zlib'

const [helder, out] = process.argv.slice(2)
// (a scenario and the story of the same moment; null: none. Viewer/fit and
// Viewer/Markdown, dark and light, were the same pixels as App/Photo full
// size and App/Markdown, and went: the scenarios show them)
const pairs = {
  'App/Grid, dark': 'Browser/grid, dark',
  'App/Grid, light': 'Browser/grid, light',
  'App/List, dark': 'Browser/list, dark',
  'App/List, light': 'Browser/list, light',
  'App/Several selected': 'Browser/several selected',
  'App/Photo full size': null,
  'App/PDF': null,
  'App/Markdown, dark': null,
  'App/Markdown, light': null,
  'App/Inspector, photo': 'Browser/inspector, photo',
  'App/No results': 'Browser/no results',
  'App/Search focused, dark': 'Browser/search focused, dark',
  'App/Search focused, light': 'Browser/search focused, light',
  'App/Empty folder': 'Browser/empty',
  'App/Folder that cannot be read': 'Browser/missing folder',
  'App/Phone, folder': 'Phone/Folder',
  'App/Phone, photo': 'Phone/Full size',
  'App/Tablet, folder': 'Tablet/Folder, sidebar'
}
fs.rmSync(out, {recursive: true, force: true})
fs.mkdirSync(path.join(out, 'stills'), {recursive: true})

// (a copy of the viewer, a repository of its own; keep: its scenarios kept,
// by a test, its stories left out; drop: files left out)
function copy(name, keep, drop = []) {
  const dir = path.resolve(out, 'viewer-' + name)
  fs.cpSync('apps/viewer', dir, {recursive: true, filter: f => !/\/(bin|node_modules)$/.test(f)})
  if (keep) {
    const f = path.join(dir, 'src/viewer/Viewer.scenario.hx')
    const text = fs.readFileSync(f, 'utf8'), at = text.indexOf('final ')
    fs.writeFileSync(f, text.slice(0, at) + text.slice(at).split(/\n(?=final )/).filter(keep).join('\n'))
  }
  for (const s of fs.readdirSync(path.join(dir, 'tests/viewer')))
    if (keep && s.endsWith('.story.hx')) fs.rmSync(path.join(dir, 'tests/viewer', s))
  for (const f of drop) fs.rmSync(path.join(dir, f))
  execFileSync('git', ['init', '-q', '-b', 'studio', dir])
  return dir
}

let port = 47600
// (the screens' program's resident memory, MB)
function rss(dir) {
  const ps = execFileSync('ps', ['-axo', 'rss=,command=']).toString().split('\n').find(l => l.includes(path.join(dir, 'bin/studio/')) && l.includes('/screens'))
  return ps ? Number(ps.trim().split(/\s+/)[0]) / 1024 : NaN
}

// the studio on dir until f is done with it: f(call, wait)
async function studio(dir, f) {
  const p = port++, log = path.join(out, path.basename(dir) + '.log')
  const script = path.join(out, 'script.json')
  fs.writeFileSync(script, JSON.stringify({events: [{t: 100000, type: 'mark', name: 'end'}]}))
  const child = spawn(helder, ['run', '--headless', 'apps/studio', '--script', script, '--size', '1180x740', '--snap', path.join(out, 'end.png'), '--at', 'mark:end',
    '--', dir, '--mcp-port', String(p)], {env: {...process.env, HELDER_BACKGROUND: '1'}, detached: true})
  let text = ''
  for (const s of [child.stdout, child.stderr]) s.on('data', d => { text += d; fs.appendFileSync(log, d) })
  const wait = async (re, s = 400) => {
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

const differ = (a, b) => {
  if (a.w !== b.w || a.h !== b.h) return a.w * a.h
  let n = 0
  for (let i = 0; i < a.w * a.h; i++)
    for (let k = 0; k < 3; k++) if (a.px[i * a.bpp + k] !== b.px[i * b.bpp + k]) { n++; break }
  return n
}
// (how many colours: a still that is one is not drawn)
const colours = a => {
  const seen = new Set()
  for (let i = 0; i < a.w * a.h && seen.size < 3; i += 7) seen.add(a.px.readUIntBE(i * a.bpp, 3))
  return seen.size
}
// (a screen's still, once it has one: a cold build's are written a moment after they are shown)
async function snap(call, screen) {
  let r = await call('run.snap', {screen})
  for (let i = 0; i < 120 && /has no frame yet/.test(r?.content?.[0]?.text ?? ''); i++) {
    await new Promise(r => setTimeout(r, 250))
    r = await call('run.snap', {screen})
  }
  const img = r?.content?.find(c => c.type === 'image')
  if (!img) throw new Error(`${screen}: no still (${JSON.stringify(r).slice(0, 300)})`)
  const b = Buffer.from(img.data, 'base64')
  fs.writeFileSync(path.join(out, 'stills', screen.replace(/[^A-Za-z0-9_-]+/g, '-') + '.png'), b)
  return decode(b)
}

const rows = [], results = []
let failed = 0
const shown = /all (\d+) screens shown (\d+) ms after opening [^,\s]+(?:, (\d+) ms after the screens' program started)?/

// 1. every scenario's still drawn, beside its story's
const both = copy('both')
await studio(both, async (call, wait) => {
  const m = await wait(shown)
  results.push({name: 'stories and scenarios', pass: 'cold', screens: +m[1], open: +m[2], program: m[3] ? +m[3] : null, rss: rss(both)})
  for (const [sc, st] of Object.entries(pairs)) {
    const a = await snap(call, sc)
    const drawn = colours(a) > 1
    if (!drawn) failed++
    const d = st ? differ(a, await snap(call, st)) : null
    rows.push(`| ${sc} | ${drawn ? 'yes' : '**no**'} | ${a.w}×${a.h} | ${st ?? '—'} | ${d ?? '—'}${d != null && a.w ? ` (${(100 * d / (a.w * a.h)).toFixed(1)}%)` : ''} |`)
    console.log(sc, drawn ? 'drawn' : 'NOT DRAWN', st ? `against ${st}: ${d} pixels differ` : '')
  }
})

// (until the studio's frames.hframes has stopped changing for 3 s: every still written, a minute at most)
async function written(dir) {
  const studio = path.join(dir, 'bin/studio')
  let last = '', same = 0
  for (let i = 0; i < 240 && same < 12; i++) {
    await new Promise(r => setTimeout(r, 250))
    const f = fs.existsSync(studio) ? fs.readdirSync(studio).map(d => path.join(studio, d, 'frames.hframes')).find(f => fs.existsSync(f)) : null
    const now = f ? `${fs.statSync(f).size}:${fs.statSync(f).mtimeMs}` : ''
    same = now !== '' && now === last ? same + 1 : 0
    last = now
  }
}

// 2. the scenarios alone: their stills timed, cold and from the frame cache; their memory
const alone = copy('scenarios', () => true)
for (const pass of ['cold', 'cached']) {
  const r = await studio(alone, async (call, wait) => {
    const m = await wait(shown)
    await written(alone)
    return {screens: +m[1], open: +m[2], program: m[3] ? +m[3] : null, rss: rss(alone)}
  })
  results.push({name: 'scenarios', pass, ...r})
  console.log('scenarios', pass, JSON.stringify(r))
}

// (the stories alone, the same way)
const stories = copy('stories', null, ['src/viewer/Viewer.scenario.hx'])
results.push({name: 'stories', pass: 'cold', ...await studio(stories, async (call, wait) => {
  const m = await wait(shown)
  await new Promise(r => setTimeout(r, 3000))
  return {screens: +m[1], open: +m[2], program: m[3] ? +m[3] : null, rss: rss(stories)}
})})

// 3. memory a screen: one scenario against all of them, against the stories
const one = copy('one', l => l.includes('"App/Grid, dark"'))
const single = await studio(one, async (call, wait) => {
  await wait(shown)
  await new Promise(r => setTimeout(r, 3000))
  return rss(one)
})
const all = results.find(r => r.name === 'scenarios' && r.pass === 'cold'), told = results.find(r => r.name === 'stories')
const md = ['# The viewer\'s scenarios in the studio', '', '| scenario | drawn | size | story of the same moment | pixels that differ |', '|---|---|---|---|---|']
  .concat(rows)
  .concat(['', '| screens | pass | n | shown after opening (ms) | after the program started (ms) | program RSS (MB) |', '|---|---|---|---|---|---|'])
  .concat(results.map(r => `| ${r.name} | ${r.pass} | ${r.screens} | ${r.open} | ${r.program ?? '—'} | ${isNaN(r.rss) ? '—' : r.rss.toFixed(1)} |`))
  .concat(['', `Memory a scenario screen: (${all.rss.toFixed(1)} − ${single.toFixed(1)}) / ${all.screens - 1} = ${((all.rss - single) / (all.screens - 1)).toFixed(2)} MB;`
    + ` a story screen: (${told.rss.toFixed(1)} − ${single.toFixed(1)}) / ${told.screens - 1} = ${((told.rss - single) / (told.screens - 1)).toFixed(2)} MB`])
fs.writeFileSync(path.join(out, 'results.md'), md.join('\n') + '\n')
console.log(md.join('\n'))
if (failed > 0) {
  console.log(`${failed} scenario stills not drawn`)
  process.exit(1)
}
