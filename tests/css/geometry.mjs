// Chromium's layout geometry for WPT's CSS tests, node by node, for
// CssGeometryCheck to compare helder's with: each page loaded as
// goldens.mjs draws it (the same flags, fonts, viewport and URL; its
// setup copied here, since goldens.mjs's own text keys the goldens), then
// DOMSnapshot.captureSnapshot: each element's border box, an inline
// element's one rectangle a line (getClientRects), each text node's
// text boxes with their range of its data, ::before, ::after and ::marker
// as their element's; each node named by its DOM path
// (html>body>div[2]>#text). Written as JSON under
// bin/css/geometry/<key>/, keyed as the goldens are (WPT's revision,
// Chromium's version, a hash of this script and the fonts): a snapshot
// there is kept. The directory is written to bin/css/geometry/current.
//
//   node tests/css/geometry.mjs [filter...]   (a directory or name's part: those alone)
//   node tests/css/geometry.mjs --serve       (a line of JSON in, {html}, a line out: its geometry)
import {createRequire} from 'node:module'
import {execFileSync} from 'node:child_process'
import {createHash} from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import readline from 'node:readline'

const require = createRequire(path.resolve('package.json'))
let pw
try {
  pw = require('playwright')
} catch {
  console.error('geometry.mjs: no Playwright (bun add --no-save playwright@1.56.1 && bunx playwright install chromium)')
  process.exit(1)
}

const serve = process.argv.includes('--serve')
const filters = process.argv.slice(2).filter(a => a !== '--serve')
const pages = Number(process.env.PAGES ?? 2)
const wpt = path.resolve('bin/wpt')
const HOST = 'http://web-platform.test/'
// (a page served for --serve, at WPT's host: /fonts/ahem.css found)
const CASE = HOST + '__helder/case.html'
const revision = execFileSync('git', ['-C', wpt, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim()
// (in --serve mode stdout is the answers': what's said goes to stderr)
const log = (...a) => (serve ? console.error : console.log)(...a)

const runner = process.platform === 'win32' ? 'bin/css/CssGeometryCheck.exe' : 'bin/css/CssGeometryCheck'
const fonts = JSON.parse(execFileSync(runner, ['--fonts'], {encoding: 'utf8'}).trim().split('\n').pop())
const faces = fonts.faces.map(f => ({...f, file: path.resolve(f.file)}))

// (the tests CssReftestCheck draws on a screen: no paged media, no scripts)
const paged = dir => /^css\/css-(page|break|gcpm)/.test(dir) || dir === 'css/CSS2/page-box' || dir === 'css/CSS2/pagination'
const tests = []
if (!serve) {
  const fixtures = JSON.parse(fs.readFileSync('tests/css/fixtures/reftests.json', 'utf8'))
  for (const [dir, d] of Object.entries(fixtures.directories))
    for (const t of d.tests ?? []) {
      const needs = t.needs ?? []
      if (paged(dir) || needs.includes('print') || needs.includes('script') || needs.includes('wait')) continue
      const id = `${dir}/${t.name}`
      if (filters.length && !filters.some(f => id.includes(f))) continue
      tests.push(id)
    }
}

const TYPES = {
  '.xht': 'application/xhtml+xml', '.xhtml': 'application/xhtml+xml', '.xml': 'application/xml', '.svg': 'image/svg+xml',
  '.html': 'text/html', '.htm': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png',
  '.gif': 'image/gif', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff': 'font/woff',
  '.woff2': 'font/woff2'
}

const browser = await pw.chromium.launch({args: ['--force-color-profile=srgb', '--hide-scrollbars', '--font-render-hinting=none', '--disable-lcd-text']})
const hash = createHash('sha256').update(fs.readFileSync(new URL(import.meta.url))).update(JSON.stringify(fonts)).digest('hex').slice(0, 8)
const key = `${revision.slice(0, 12)}-chromium-${browser.version()}-${hash}`
const out = path.join('bin/css/geometry', key)
const todo = tests.filter(id => !fs.existsSync(path.join(out, id + '.json')))
if (!serve) log(`geometry.mjs: ${tests.length} tests, ${todo.length} to snapshot, Chromium ${browser.version()}`)

let html = ''
const context = await browser.newContext({viewport: {width: 800, height: 600}, deviceScaleFactor: 1})
await context.route(HOST + '**', route => {
  const url = new URL(route.request().url())
  if (url.href === CASE) return route.fulfill({status: 200, body: html, contentType: 'text/html'})
  const face = /^\/__helder\/font\/(\d+)$/.exec(url.pathname)
  if (face) return route.fulfill({status: 200, body: fs.readFileSync(faces[Number(face[1])].file), contentType: 'font/ttf'})
  const file = path.join(wpt, decodeURIComponent(url.pathname))
  if (!file.startsWith(wpt) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) return route.fulfill({status: 404, body: ''})
  route.fulfill({status: 200, body: fs.readFileSync(file), contentType: TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream'})
})

await context.addInitScript(list => {
  for (const [i, f] of list.entries())
    document.fonts.add(new FontFace(f.family, `url(/__helder/font/${i})`, {weight: String(f.weight), style: f.italic ? 'italic' : 'normal'}))
}, faces.map(f => ({family: f.family, weight: f.weight, italic: f.italic})))

// (goldens.mjs's: every font-family a generic family as helder takes it,
// a family no machine has renamed so it's skipped as helder skips it)
function families(generic) {
  const serif = generic.serif, sans = generic['sans-serif'], mono = generic.monospace
  const GENERIC = {serif, 'sans-serif': sans, monospace: mono, cursive: serif, fantasy: serif, math: serif, fangsong: serif, 'system-ui': sans,
    'ui-serif': serif, 'ui-sans-serif': sans, 'ui-rounded': sans, 'ui-monospace': mono}
  const known = new Set([...document.fonts].map(f => f.family.replace(/^["']|["']$/g, '').toLowerCase()))
  const sheets = []
  const walk = list => {
    for (const sheet of list) {
      let rules
      try { rules = sheet.cssRules } catch { continue }
      sheets.push(sheet)
      for (const r of rules) {
        if (r.styleSheet) walk([r.styleSheet])
        if (r instanceof CSSFontFaceRule) known.add(r.style.getPropertyValue('font-family').trim().replace(/^["']|["']$/g, '').toLowerCase())
      }
    }
  }
  walk(document.styleSheets)
  const fallback = `"${sans}"`
  const rewrite = value => {
    if (!value || /var\(|^\s*(inherit|initial|unset|revert|revert-layer)\s*$/i.test(value)) return null
    const items = value.match(/("[^"]*"|'[^']*'|[^,])+/g) ?? []
    return [...items.map(item => {
      const t = item.trim(), quoted = /^["']/.test(t)
      const name = quoted ? t.slice(1, -1) : t.replace(/\s+/g, ' ')
      const lower = name.toLowerCase()
      if (!quoted && GENERIC[lower]) return `"${GENERIC[lower]}"`
      if (known.has(lower)) return t
      return `"helder-none ${name.replace(/["\\]/g, '')}"`
    }), fallback].join(', ')
  }
  const fix = style => {
    const v = style.getPropertyValue('font-family'), w = rewrite(v)
    if (w != null && w !== v) style.setProperty('font-family', w, style.getPropertyPriority('font-family'))
  }
  const rules = list => {
    for (const r of list) {
      if (r.style && !(r instanceof CSSFontFaceRule)) fix(r.style)
      if (r.cssRules) rules(r.cssRules)
    }
  }
  for (const sheet of sheets) rules(sheet.cssRules)
  for (const el of document.querySelectorAll('[style]')) if (el.style) fix(el.style)
  const ua = new CSSStyleSheet()
  ua.replaceSync(`@layer helder-ua { :root { font-family: "${serif}", ${fallback} }
    :where(pre, xmp, plaintext, listing, code, kbd, samp, tt, textarea) { font-family: "${mono}", ${fallback} } }`)
  document.adoptedStyleSheets = [...document.adoptedStyleSheets, ua]
}

// (a node's name in a path: an element's lower-case name, #text; with its
// place among its parent's children of that name, [1], where there are several)
function names(kids, name) {
  const count = {}, seen = {}
  for (const k of kids) count[name(k)] = (count[name(k)] ?? 0) + 1
  return kids.map(k => {
    const n = name(k)
    seen[n] = (seen[n] ?? 0) + 1
    return count[n] > 1 ? `${n}[${seen[n]}]` : n
  })
}

// (in the page: each inline element's rectangles, by its path; names
// given as its source, a function being no argument evaluate takes)
function inlines(source) {
  const names = eval(source)
  const out = {}
  const name = n => n.nodeType === 1 ? n.nodeName.toLowerCase() : n.nodeType === 3 ? '#text' : n.nodeType === 4 ? '#cdata-section' : '#' + n.nodeType
  // (an inline box's rectangles, its lines': not those of the anonymous
  // blocks around the blocks in it, which Blink gives too)
  const lines = e => {
    const blocks = []
    const find = n => {
      for (const c of n.children) {
        const s = getComputedStyle(c)
        if (s.display === 'none' || s.position === 'absolute' || s.position === 'fixed' || s.float !== 'none') continue
        if (/^inline|^contents$/.test(s.display)) find(c)
        else blocks.push(c.getBoundingClientRect())
      }
    }
    find(e)
    const inside = (b, r) => b.left >= r.x - 0.5 && b.right <= r.x + r.width + 0.5 && b.top >= r.y - 0.5 && b.bottom <= r.y + r.height + 0.5
    return [...e.getClientRects()].filter(r => !blocks.some(b => inside(b, r))).map(r => [r.x, r.y, r.width, r.height])
  }
  const walk = (node, at) => {
    const kids = [...node.childNodes], ns = names(kids, name)
    for (const [i, k] of kids.entries()) {
      if (k.nodeType !== 1) continue
      const p = at ? `${at}>${ns[i]}` : ns[i]
      if (getComputedStyle(k).display === 'inline') out[p] = lines(k)
      if (k.namespaceURI !== 'http://www.w3.org/2000/svg') walk(k, p)
    }
  }
  walk(document, '')
  return out
}

// (the page's geometry, from its snapshot: tree order, each node's
// rectangles and text boxes; transformed subtrees named in skipped, their
// boxes not where layout put them)
async function geometry(page, cdp) {
  const inline = await page.evaluate(inlines, `(${names})`)
  const s = await cdp.send('DOMSnapshot.captureSnapshot', {computedStyles: ['display', 'transform'], includeDOMRects: false})
  const d = s.documents[0], n = d.nodes, str = i => i < 0 ? null : s.strings[i]
  const pseudo = new Map(), shadow = new Set(n.shadowRootType?.index ?? [])
  for (const [k, i] of (n.pseudoType?.index ?? []).entries()) pseudo.set(i, str(n.pseudoType.value[k]))
  const kids = n.parentIndex.map(() => [])
  for (const [i, p] of n.parentIndex.entries()) if (p >= 0) kids[p].push(i)
  const name = i => {
    const t = n.nodeType[i]
    return t === 1 ? str(n.nodeName[i]).toLowerCase() : t === 3 ? '#text' : t === 4 ? '#cdata-section' : '#' + t
  }
  // (each node's path: pseudo-elements as ::before under their element, a shadow tree's nodes none)
  // (in tree order as helder's Geometry has it: an element, its ::marker and ::before, its children, its ::after)
  const paths = new Array(n.parentIndex.length).fill(null), order = new Array(n.parentIndex.length).fill(Infinity)
  let rank = 0
  const walk = (i, at) => {
    const real = kids[i].filter(k => !pseudo.has(k) && !shadow.has(k)), ns = names(real, name)
    const own = kids[i].filter(k => pseudo.has(k) && at)
    for (const k of own) paths[k] = `${at}>::${pseudo.get(k)}`
    for (const k of own) if (pseudo.get(k) !== 'after') order[k] = rank++
    for (const [j, k] of real.entries()) {
      paths[k] = at ? `${at}>${ns[j]}` : ns[j]
      order[k] = rank++
      if (name(k).replace(/^.*:/, '') !== 'svg') walk(k, paths[k])
    }
    for (const k of own) if (pseudo.get(k) === 'after') order[k] = rank++
  }
  walk(0, '')
  const nodes = new Map(), skipped = []
  const entry = i => {
    let e = nodes.get(i)
    if (!e) nodes.set(i, e = {index: i, path: paths[i], rects: [], text: []})
    return e
  }
  const layout = d.layout
  for (const [k, i] of layout.nodeIndex.entries()) {
    const p = paths[i]
    if (p == null || name(i) === 'br' || skipped.some(s => p === s || p.startsWith(s + '>'))) continue
    const styles = layout.styles[k], transform = str(styles[1])
    if (transform && transform !== 'none') {
      skipped.push(p)
      continue
    }
    const text = str(layout.text[k])
    if (text != null) continue
    const e = entry(i)
    if (e.rects.length === 0) e.rects = inline[p] ?? [layout.bounds[k]]
  }
  const t = d.textBoxes
  for (const [k, l] of t.layoutIndex.entries()) {
    const i = layout.nodeIndex[l], p = paths[i]
    if (p == null || n.nodeType[i] === 1 && !pseudo.has(i) || skipped.some(s => p.startsWith(s + '>'))) continue
    const value = pseudo.has(i) ? str(layout.text[l]) : str(n.nodeValue[i]) ?? ''
    // (the text after a ::first-letter: its offsets from the letter's end)
    const own = str(layout.text[l]) ?? value, shift = !pseudo.has(i) && own.length < value.length && value.endsWith(own) ? value.length - own.length : 0
    const [a, b] = trim(value, shift + t.start[k], shift + t.start[k] + t.length[k])
    entry(i).text.push([...t.bounds[k], a, b])
  }
  const list = [...nodes.values()].sort((a, b) => order[a.index] - order[b.index]).map(({path, rects, text}) => ({path, rects, ...(text.length ? {text} : {})}))
  return {nodes: list, ...(skipped.length ? {skipped} : {})}
}

// (a text box's range without white space at its ends: where each engine
// ends a box around collapsed spaces is its own)
function trim(s, a, b) {
  const space = c => c === ' ' || c === '\t' || c === '\n' || c === '\r' || c === '\f'
  while (a < b && space(s[a])) a++
  while (b > a && space(s[b - 1])) b--
  return [a, b]
}

async function load(page, url) {
  await page.goto(url, {waitUntil: 'load', timeout: 20000})
  await page.evaluate(families, fonts.generic)
  await page.evaluate(async () => {
    document.documentElement.getBoundingClientRect()
    await document.fonts.ready
    await new Promise(r => requestAnimationFrame(() => r()))
    await document.fonts.ready
  })
}

async function open() {
  const page = await context.newPage()
  const cdp = await context.newCDPSession(page)
  await cdp.send('Page.setFontFamilies', {
    fontFamilies: {standard: fonts.generic.serif, serif: fonts.generic.serif, sansSerif: fonts.generic['sans-serif'], fixed: fonts.generic.monospace,
      cursive: fonts.generic.serif, fantasy: fonts.generic.serif}
  })
  return {page, cdp}
}

if (serve) {
  // (one page for every case: the property's cases one after another)
  const {page, cdp} = await open()
  const lines = readline.createInterface({input: process.stdin})
  for await (const line of lines) {
    if (!line.trim()) continue
    let answer
    try {
      html = JSON.parse(line).html
      await load(page, CASE)
      answer = await geometry(page, cdp)
    } catch (e) {
      answer = {error: String(e.message ?? e).split('\n')[0]}
    }
    process.stdout.write(JSON.stringify(answer) + '\n')
  }
  await browser.close()
  process.exit(0)
}

const LIMIT = 30000
let done = 0, failed = 0
async function lane(queue) {
  let tab = await open()
  for (let id; (id = queue.shift()) !== undefined;) {
    let timer
    const limit = new Promise((_, fail) => timer = setTimeout(() => fail(new Error(`no snapshot after ${LIMIT / 1000} s`)), LIMIT))
    try {
      const g = await Promise.race([load(tab.page, HOST + id).then(() => geometry(tab.page, tab.cdp)), limit])
      const file = path.join(out, id + '.json')
      fs.mkdirSync(path.dirname(file), {recursive: true})
      fs.writeFileSync(file, JSON.stringify(g))
    } catch (e) {
      failed++
      log(`geometry.mjs: ${id}: ${String(e.message ?? e).split('\n')[0]}`)
      tab.page.close().catch(() => {})
      tab = await open()
    } finally {
      clearTimeout(timer)
    }
    if (++done % 500 === 0) log(`geometry.mjs: ${done} of ${todo.length}`)
  }
  await tab.page.close()
}

try {
  const queue = [...todo]
  await Promise.all(Array.from({length: Math.max(1, Math.min(pages, queue.length))}, () => lane(queue)))
} finally {
  await browser.close()
}
log(`geometry.mjs: ${done - failed} snapshots, ${failed} failed: ${out}`)
fs.mkdirSync('bin/css/geometry', {recursive: true})
fs.writeFileSync('bin/css/geometry/current', out + '\n')
