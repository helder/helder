// Goldens for WPT's noref tests (visual tests without a reference): each
// in-scope one of fixtures/reftests.json drawn by headless Chromium
// (Playwright, the version CI's setup pins: bun add --no-save
// playwright@1.56.1) at 800 by 600, at WPT's URL (bin/wpt served as
// http://web-platform.test/, so /fonts/ahem.css is found), its generic
// families the faces helder takes (CssReftestCheck --fonts), and written
// as a PNG under bin/css/goldens/<key>/, the key WPT's revision, Chromium's
// version and the platform. Not committed: made on demand, a golden there
// is kept; CI caches the directory by the key. One browser, PAGES (2)
// pages at a time. The directory is written to bin/css/goldens/current.
//
//   node tests/css/goldens.mjs [filter...]    (a directory or name's part: those alone)
import {createRequire} from 'node:module'
import {execFileSync} from 'node:child_process'
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

// (the faces helder's generic families resolve to, so text is drawn in the same fonts)
const runner = process.platform === 'win32' ? 'bin/css/CssReftestCheck.exe' : 'bin/css/CssReftestCheck'
const fonts = JSON.parse(execFileSync(runner, ['--fonts'], {encoding: 'utf8'}).trim().split('\n').pop())

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

const browser = await pw.chromium.launch({args: ['--force-color-profile=srgb', '--hide-scrollbars', '--font-render-hinting=none']})
const key = `${revision.slice(0, 12)}-chromium-${browser.version()}-${process.platform}-${process.arch}`
const out = path.join('bin/css/goldens', key)
const todo = tests.filter(id => !fs.existsSync(path.join(out, id + '.png')))
console.log(`goldens.mjs: ${tests.length} noref tests, ${todo.length} to draw, Chromium ${browser.version()}, ${JSON.stringify(fonts)}`)

const context = await browser.newContext({viewport: {width: 800, height: 600}, deviceScaleFactor: 1})
await context.route(HOST + '**', route => {
  const url = new URL(route.request().url())
  const file = path.join(wpt, decodeURIComponent(url.pathname))
  if (!file.startsWith(wpt) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) return route.fulfill({status: 404, body: ''})
  route.fulfill({status: 200, body: fs.readFileSync(file), contentType: TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream'})
})

let done = 0, failed = 0
async function draw(page, id) {
  await page.goto(HOST + id, {waitUntil: 'load', timeout: 20000})
  await page.evaluate(() => document.fonts.ready)
  // (grayscale antialiasing, as helder's rasterizer draws text: not macOS's heavier smoothing)
  await page.addStyleTag({content: '* { -webkit-font-smoothing: antialiased !important }'})
  const file = path.join(out, id + '.png')
  fs.mkdirSync(path.dirname(file), {recursive: true})
  await page.screenshot({path: file, clip: {x: 0, y: 0, width: 800, height: 600}, animations: 'disabled'})
}

async function lane(queue) {
  const page = await context.newPage()
  // (once a page: Chromium takes them once)
  const cdp = await context.newCDPSession(page)
  await cdp.send('Page.setFontFamilies', {
    fontFamilies: {standard: fonts.serif, serif: fonts.serif, sansSerif: fonts['sans-serif'], fixed: fonts.monospace, cursive: fonts.serif, fantasy: fonts.serif}
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
