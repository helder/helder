// Goldens for WPT's noref tests (visual tests without a reference): each
// in-scope one of fixtures/reftests.json drawn by headless Chromium
// (Playwright, the version CI's setup pins: bun add --no-save
// playwright@1.56.1) at 800 by 600, at WPT's URL (bin/wpt served as
// http://web-platform.test/, so /fonts/ahem.css is found), with helder's
// fonts alone (CssReftestCheck --fonts: DejaVu for the generic families,
// Ahem and WPT's test fonts; none of the machine's), and written as a PNG
// under bin/css/goldens/<key>/, the key WPT's revision, Chromium's version
// and a hash of this script and the fonts: the same on every machine. Not
// committed: made on demand, a golden there is kept; CI caches the
// directory by the key. One browser, PAGES (2) pages at a time. The
// directory is written to bin/css/goldens/current.
//
//   node tests/css/goldens.mjs [filter...]    (a directory or name's part: those alone)
import {createRequire} from 'node:module'
import {execFileSync} from 'node:child_process'
import {createHash} from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'

const require = createRequire(path.resolve('package.json'))
let pw
try {
  pw = require('playwright')
} catch {
  console.error('goldens.mjs: no Playwright (bun add --no-save playwright@1.56.1 && bunx playwright install chromium)')
  process.exit(1)
}

const wpt = path.resolve('bin/wpt')
const filters = process.argv.slice(2)
const pages = Number(process.env.PAGES ?? 2)
const HOST = 'http://web-platform.test/'
const fixtures = JSON.parse(fs.readFileSync('tests/css/fixtures/reftests.json', 'utf8'))
const revision = execFileSync('git', ['-C', wpt, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim()

// (the fonts helder has, CssReftestCheck --fonts: DejaVu, Ahem, WPT's test
// fonts; each given to Chromium as a web font, so no machine's own is used)
const runner = process.platform === 'win32' ? 'bin/css/CssReftestCheck.exe' : 'bin/css/CssReftestCheck'
const fonts = JSON.parse(execFileSync(runner, ['--fonts'], {encoding: 'utf8'}).trim().split('\n').pop())
const faces = fonts.faces.map(f => ({...f, file: path.resolve(f.file)}))

// (as CssReftestCheck skips them: paged media, scripts)
const paged = dir => /^css\/css-(page|break|gcpm)/.test(dir) || dir === 'css/CSS2/page-box' || dir === 'css/CSS2/pagination'
const tests = []
for (const [dir, d] of Object.entries(fixtures.directories))
  for (const t of d.tests ?? []) {
    const needs = t.needs ?? []
    if (t.type !== 'noref' || paged(dir) || needs.includes('print') || needs.includes('script') || needs.includes('wait')) continue
    const id = `${dir}/${t.name}`
    if (filters.length && !filters.some(f => id.includes(f))) continue
    tests.push(id)
  }

const TYPES = {
  '.xht': 'application/xhtml+xml', '.xhtml': 'application/xhtml+xml', '.xml': 'application/xml', '.svg': 'image/svg+xml',
  '.html': 'text/html', '.htm': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png',
  '.gif': 'image/gif', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff': 'font/woff',
  '.woff2': 'font/woff2'
}

const flags = (process.env.GOLDENS_FLAGS ?? '').split(' ').filter(f => f)
const scale = Number(process.env.GOLDENS_SCALE ?? 1)
const browser = await pw.chromium.launch({args: ['--force-color-profile=srgb', '--hide-scrollbars', '--font-render-hinting=none', ...flags]})
// (the key: WPT's revision, Chromium's version, and how goldens are drawn (this
// script, the fonts): the same on every machine)
const drawing = createHash('sha256').update(fs.readFileSync(new URL(import.meta.url))).update(JSON.stringify(fonts)).update(flags.length || scale !== 1 || process.env.FONTCONFIG_FILE ? JSON.stringify([flags, scale, process.env.FONTCONFIG_FILE]) : '').digest('hex').slice(0, 8)
const key = `${revision.slice(0, 12)}-chromium-${browser.version()}-${drawing}`
const out = path.join('bin/css/goldens', key)
const todo = tests.filter(id => !fs.existsSync(path.join(out, id + '.png')))
console.log(`goldens.mjs: ${tests.length} noref tests, ${todo.length} to draw, Chromium ${browser.version()}, ${faces.length} faces, ${JSON.stringify(fonts.generic)}`)

const context = await browser.newContext({viewport: {width: 800, height: 600}, deviceScaleFactor: scale})
await context.route(HOST + '**', route => {
  const url = new URL(route.request().url())
  const face = /^\/__helder\/font\/(\d+)$/.exec(url.pathname)
  if (face) return route.fulfill({status: 200, body: fs.readFileSync(faces[Number(face[1])].file), contentType: 'font/ttf'})
  const file = path.join(wpt, decodeURIComponent(url.pathname))
  if (!file.startsWith(wpt) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) return route.fulfill({status: 404, body: ''})
  route.fulfill({status: 200, body: fs.readFileSync(file), contentType: TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream'})
})

// (every face, as a web font: found before any of the machine's by its name)
await context.addInitScript(list => {
  for (const [i, f] of list.entries())
    document.fonts.add(new FontFace(f.family, `url(/__helder/font/${i})`, {weight: String(f.weight), style: f.italic ? 'italic' : 'normal'}))
}, faces.map(f => ({family: f.family, weight: f.weight, italic: f.italic})))

// (in the page, loaded: every font-family its sheets and style attributes
// give, a generic family as the face helder takes for it (Chromium's own
// settings can't name a web font), a family helder has kept, any other
// renamed to one no machine has, so Chromium skips it as helder does; the
// UA's monospace elements' as a layer below the page's)
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
  // (helder's fallback for characters its faces lack: DejaVu Sans, SystemFonts.FALLBACK; the machine's after it)
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

let done = 0, failed = 0
async function draw(page, id) {
  await page.goto(HOST + id, {waitUntil: 'load', timeout: 20000})
  await page.evaluate(families, fonts.generic)
  await page.evaluate(async () => {
    document.documentElement.getBoundingClientRect()
    await document.fonts.ready
    await new Promise(r => requestAnimationFrame(() => r()))
    await document.fonts.ready
  })
  // (grayscale antialiasing, as helder's rasterizer draws text: not macOS's heavier smoothing)
  await page.addStyleTag({content: '* { -webkit-font-smoothing: antialiased !important }'})
  const file = path.join(out, id + '.png')
  fs.mkdirSync(path.dirname(file), {recursive: true})
  await page.screenshot({path: file, clip: {x: 0, y: 0, width: 800, height: 600}, animations: 'disabled', scale: 'css'})
}

async function lane(queue) {
  const page = await context.newPage()
  // (the initial font, once a page: Chromium takes them once)
  const cdp = await context.newCDPSession(page)
  await cdp.send('Page.setFontFamilies', {
    fontFamilies: {standard: fonts.generic.serif, serif: fonts.generic.serif, sansSerif: fonts.generic['sans-serif'], fixed: fonts.generic.monospace,
      cursive: fonts.generic.serif, fantasy: fonts.generic.serif}
  })
  for (let id; (id = queue.shift()) !== undefined;) {
    try {
      await draw(page, id)
    } catch (e) {
      failed++
      console.error(`goldens.mjs: ${id}: ${String(e.message ?? e).split('\n')[0]}`)
    }
    if (++done % 250 === 0) console.log(`goldens.mjs: ${done} of ${todo.length}`)
  }
  await page.close()
}

try {
  const queue = [...todo]
  await Promise.all(Array.from({length: Math.max(1, Math.min(pages, queue.length))}, () => lane(queue)))
} finally {
  await browser.close()
}
console.log(`goldens.mjs: ${done - failed} drawn, ${failed} failed: ${out}`)
fs.mkdirSync('bin/css/goldens', {recursive: true})
fs.writeFileSync('bin/css/goldens/current', out + '\n')
