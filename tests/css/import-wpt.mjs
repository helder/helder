// Makes tests/css/fixtures from web-platform-tests at REVISION, read
// statically (tests/css/README.md); run from the repository's root:
//   node tests/css/import-wpt.mjs [wpt checkout]   (default bin/wpt, cloned if missing)
import fs from 'node:fs'
import path from 'node:path'
import {spawnSync} from 'node:child_process'
import {bindings, calls} from './wpt-js.mjs'

const REVISION = 'bc5ea7a9006b77c12118534bf7d2953e530d811f'
const SUITES = ['css/CSS2', 'css/css-page', 'css/css-break', 'css/css-gcpm']
const root = path.resolve(process.argv[2] ?? 'bin/wpt')
const out = 'tests/css/fixtures'

if (!fs.existsSync(root)) {
  sh('git', ['clone', '--filter=blob:none', '--no-checkout', 'https://github.com/web-platform-tests/wpt.git', root])
  sh('git', ['-C', root, 'sparse-checkout', 'set', '--no-cone', '/css/', '/dom/nodes/', '/LICENSE.md'])
  sh('git', ['-C', root, 'checkout', '-q', REVISION])
}
const head = sh('git', ['-C', root, 'rev-parse', 'HEAD']).trim()
if (head !== REVISION) throw Error(`${root} is at ${head}, not ${REVISION} (check it out, or move REVISION)`)
fs.mkdirSync(out, {recursive: true})
fs.copyFileSync(path.join(root, 'LICENSE.md'), 'tests/css/WPT-LICENSE.md')

const scope = JSON.parse(fs.readFileSync('src/helder/css/scope.json', 'utf8'))
const module = new Map(Object.entries(scope.modules).flatMap(([m, names]) => names.map(n => [n, m])))
const report = []

// ---- values.json: the parsing, computed and inheritance helpers' calls
const HELPERS = new Set(['test_valid_value', 'test_invalid_value', 'test_computed_value', 'test_shorthand_value',
  'fuzzy_test_valid_color', 'fuzzy_test_computed_color', 'fuzzy_test_valid_color_property',
  'fuzzy_test_computed_color_property', 'assert_inherited', 'assert_not_inherited'])
const files = [], fileIndex = new Map(), values = {}
const stats = {calls: 0, extracted: 0, outOfScope: 0, duplicates: 0, unreadable: {}, outProperties: {}}
const seen = new Set()
const add = (prop, kind, row) => {
  const key = JSON.stringify([prop, kind, row.slice(0, -1)])
  if (seen.has(key)) return stats.duplicates++
  seen.add(key)
  const p = values[prop] ??= {}
  ;(p[kind] ??= []).push(row)
  stats.extracted++
}
// (a call counted once, however many loop items or helper calls it is read for)
const unreadSeen = new Set()
const unreadable = (why, at) => {
  const reason = why.replace(/\(.*\)$/, '').trim()
  if (unreadSeen.has(at + reason)) return
  unreadSeen.add(at + reason)
  stats.unreadable[reason] = (stats.unreadable[reason] ?? 0) + 1
}
for (const file of walk(path.join(root, 'css'))) {
  const rel = path.relative(root, file)
  if (/\/(support|resources|reference)\//.test(rel) || !/\.(html?|xht|xhtml|svg|js)$/.test(rel)) continue
  const text = fs.readFileSync(file, 'utf8')
  if (![...HELPERS].some(h => text.includes(h + '('))) continue
  const sources = rel.endsWith('.js') ? [text] : scripts(text)
  for (const src of sources) for (const c of calls(src, HELPERS)) {
    stats.calls++
    const color = c.name.startsWith('fuzzy_') && !c.name.endsWith('_property')
    const a = color ? ['color', ...c.args] : c.args
    const errors = (c.errors ?? []).map(e => ({...e, index: e.index + (color ? 1 : 0)}))
    // (which arguments the row needs: an unreadable title or option is left out)
    const needs = c.name === 'test_invalid_value' ? 2 : c.name.startsWith('fuzzy_') ? 4 : 3
    const bad = errors.find(e => e.index < needs)
    // (a call on a property out of scope is that, read or not)
    const named = typeof a[0] === 'string' && !errors.some(e => e.index === 0)
    if (bad && named && !a[0].startsWith('--') && !module.has(a[0].replace(/[A-Z]/g, x => '-' + x.toLowerCase()))) {
      stats.outOfScope++
      continue
    }
    if (bad) {
      unreadable(bad.why, `${rel} ${c.at}`)
      continue
    }
    if (typeof a[0] !== 'string' || typeof a[1] !== 'string' && !c.name.includes('inherited')) {
      unreadable('not a string', `${rel} ${c.at}`)
      continue
    }
    const prop = a[0].startsWith('--') ? a[0] : a[0].replace(/[A-Z]/g, x => '-' + x.toLowerCase())
    const key = prop.startsWith('--') ? '--*' : prop
    if (!module.has(key) && key !== '--*') {
      stats.outOfScope++
      stats.outProperties[prop] = (stats.outProperties[prop] ?? 0) + 1
      continue
    }
    if (!fileIndex.has(rel)) fileIndex.set(rel, files.push(rel) - 1)
    const f = fileIndex.get(rel), custom = key === '--*' ? [prop] : []
    const expected = a[2] === undefined ? null : a[2]
    switch (c.name) {
      case 'test_valid_value': add(key, 'valid', [...custom, a[1], expected, f]); break
      case 'test_invalid_value': add(key, 'invalid', [...custom, a[1], f]); break
      case 'test_computed_value': add(key, 'computed', [...custom, a[1], expected, f]); break
      case 'test_shorthand_value': add(key, 'shorthand', [a[1], a[2], f]); break
      case 'fuzzy_test_valid_color': case 'fuzzy_test_valid_color_property':
        add(key, 'valid', [...custom, a[1], expected, f, ...a[3] != null ? [a[3]] : []]); break
      case 'fuzzy_test_computed_color': case 'fuzzy_test_computed_color_property':
        add(key, 'computed', [...custom, a[1], expected, f, ...a[3] != null ? [a[3]] : []]); break
      case 'assert_inherited': add(key, 'inherits', [true, a[1] ?? null, a[2] ?? null, f]); break
      case 'assert_not_inherited': add(key, 'inherits', [false, a[1] ?? null, a[2] ?? null, f]); break
    }
  }
}
const sorted = Object.fromEntries(Object.keys(values).sort().map(k => [k, values[k]]))
writeJson(out + '/values.json', {
  source: 'web-platform-tests', revision: REVISION, license: 'BSD-3-Clause (tests/css/WPT-LICENSE.md)',
  rows: {
    valid: '[specified, serialized (null: as specified; an array: any of them), file, epsilon?]',
    invalid: '[specified, file]',
    computed: '[specified, computed (null: as specified; an array: any of them), file, epsilon?]',
    shorthand: '[specified, {longhand: serialized}, file]',
    inherits: '[inherited, initial computed value, another value, file]',
    custom: "--*'s rows start with the property's name"
  },
  files, properties: sorted
}, 4)

// ---- selectors.json: dom/nodes/selectors.js, and the document it runs on
const selectorsJs = fs.readFileSync(path.join(root, 'dom/nodes/selectors.js'), 'utf8')
const env = bindings(selectorsJs)
const types = bits => [['qsa', 0x01], ['find', 0x04], ['match', 0x10]].filter(([, b]) => bits & b).map(([n]) => n)
const selector = s => ({...s, ...(s.testType != null ? {testType: types(s.testType)} : {})})
for (const name of ['invalidSelectors', 'validSelectors', 'scopedSelectors'])
  if (!Array.isArray(env.get(name))) throw Error('selectors.js: no literal ' + name)
fs.copyFileSync(path.join(root, 'dom/nodes/ParentNode-querySelector-All-content.html'), out + '/selectors.html')
fs.copyFileSync(path.join(root, 'dom/nodes/ParentNode-querySelector-All-content.xht'), out + '/selectors.xht')
writeJson(out + '/selectors.json', {
  source: 'web-platform-tests dom/nodes/selectors.js', revision: REVISION, license: 'BSD-3-Clause (tests/css/WPT-LICENSE.md)',
  document: 'selectors.html (ParentNode-querySelector-All-content.html; selectors.xht its XHTML twin)',
  setup: 'ParentNode-querySelector-All.js adds to the document\'s body before running: <null> and <undefined> elements; '
    + 'div#any-namespace and div#no-namespace, each with four divs (ids any-namespace-div1..4, no-namespace-div1..4) '
    + 'in the HTML namespace, the HTML namespace again, no namespace and http://www.example.org/ns; and on '
    + 'span#attr-presence-i1 a title="" attribute in http://www.example.org/ns',
  fields: 'name; selector; expect: the ids matched, in document order; exclude: the contexts it is not run in '
    + '(document, element, fragment, detached, html, xhtml); level: the CSS or Selectors level it came in; '
    + 'testType: qsa (querySelector[All]), match (matches()), find; ctx and ref: a scoped test\'s context and :scope',
  invalid: env.get('invalidSelectors'), valid: env.get('validSelectors').map(selector),
  scoped: env.get('scopedSelectors').map(selector)
}, 2)
report.push(`selectors.json: ${env.get('invalidSelectors').length} invalid, ${env.get('validSelectors').length} valid, ${env.get('scopedSelectors').length} scoped selectors.`)

// ---- reftests.json: the CSS2, css-page, css-break and css-gcpm tests, classified
const DEFERRED = [
  [/writing-mode|text-orientation|text-combine-upright/, 'writing-mode'],
  [/(^|[^-\w])columns\s*:|(^|[^-\w])column-(count|width|span|fill|rule)/, 'multicol'],
  [/float\s*:\s*footnote|::footnote|footnote-(display|policy)/, 'footnotes'],
  [/@layer\b/, '@layer'], [/@container\b|container-type\s*:/, '@container'], [/@scope\b/, '@scope'],
  [/shape-outside|shape-inside/, 'shapes'], [/flow-(into|from)\s*:/, 'regions'],
  [/<(input|select|textarea|button)\b/i, 'forms'],
  [/preserve-3d|perspective\s*:|(rotate|translate|scale)(3d|X|Y|Z)\(|matrix3d\(/, '3D transforms']
]
const HELP_DEFERRED = [
  [/css-writing-modes/, 'writing-mode'], [/css-multicol/, 'multicol'], [/#footnote|css-gcpm-3\/#.*footnote/, 'footnotes'],
  [/css-regions/, 'regions'], [/css-shapes/, 'shapes'], [/css-forms/, 'forms'], [/css-contain/, 'containment'],
  [/css-conditional-5/, '@container'], [/css-ruby/, 'ruby'], [/css-anchor-position/, 'anchor positioning'],
  [/css-sizing-4/, 'Sizing 4'], [/css-text-4|css-text-decor-4|css-overflow-4|css-inline/, 'past checkpoint 1\'s modules']
]
const FLAGS_OUT = {
  interact: 'interact: needs a person', dom: 'script: needs JavaScript', animated: 'animated: a page is still',
  history: 'history: :visited', userstyle: 'userstyle: needs a user style sheet set by hand',
  http: 'http: needs an HTTP server\'s headers', asis: 'http: needs an HTTP server\'s headers', scroll: 'scroll: a page doesn\'t scroll'
}
const isTest = rel => !/\/(support|resources|reference|references|ref)\//.test(rel)
  && !/(^|[-_/])(not)?ref([-_.]|\d|$)|-ref\d*\.|\.(ref|notref)\./.test(path.basename(rel))
  && /\.(html?|xht|xhtml|svg)$/.test(rel)
const tests = [], summary = new Map()
for (const suite of SUITES) for (const file of walk(path.join(root, suite))) {
  const rel = path.relative(root, file)
  if (!isTest(rel)) continue
  const text = fs.readFileSync(file, 'utf8')
  const t = describe(rel, text)
  if (!t) continue
  t.scope = classify(t, text)
  tests.push(t)
}
// (grouped by directory, paths and references from it; a reftest's type left out)
const dirs = {}
for (const t of tests) {
  const dir = path.posix.dirname(t.path), d = dirs[dir] ??= {tests: [], out: []}
  const name = path.posix.basename(t.path)
  if (t.scope !== true) {
    d.out.push([name, t.type, t.scope])
    continue
  }
  const local = refs => refs.map(([r, rel, own]) => [path.posix.relative(dir, r), rel, ...own ? [local(own)] : []])
  const row = {name, ...t.type !== 'reftest' ? {type: t.type} : {}, refs: local(t.refs), help: t.help, flags: t.flags, fuzzy: t.fuzzy, needs: t.needs}
  d.tests.push(Object.fromEntries(Object.entries(row).filter(([, v]) => !(Array.isArray(v) && !v.length))))
}
for (const d of Object.values(dirs)) {
  if (!d.tests.length) delete d.tests
  if (!d.out.length) delete d.out
}
writeJson(out + '/reftests.json', {
  source: 'web-platform-tests', revision: REVISION, license: 'BSD-3-Clause (tests/css/WPT-LICENSE.md)',
  fields: 'directories (from the WPT root), each with tests in scope: name; type: crash (else a reftest); '
    + 'refs: [path from the directory, match|mismatch, the reference\'s own refs?]; help: <link rel=help>s; '
    + 'flags: <meta name=flags>; fuzzy: <meta name=fuzzy>s; needs: ahem, script, print (-print: paged), wait '
    + '(reftest-wait), image, svg, xml (each left out when empty); and out: [name, type (reftest, crash, '
    + 'testharness, manual, visual), why not]',
  directories: dirs
}, 4)

// ---- the report, into tests/css/README.md between its markers
const n = (a, b) => b[1] - a[1]
const table = (head, rows) => [`| ${head.join(' | ')} |`, `| ${head.map(() => '---').join(' | ')} |`, ...rows.map(r => `| ${r.join(' | ')} |`)].join('\n')
const inScope = tests.filter(t => t.scope === true)
const bySuite = SUITES.map(s => {
  const ts = tests.filter(t => t.path.startsWith(s + '/'))
  return [s, ts.length, ts.filter(t => t.scope === true).length, ts.filter(t => t.scope === true && t.needs.includes('ahem')).length, ts.filter(t => t.scope === true && t.needs.includes('print')).length]
})
const groups = new Map()
for (const t of tests) {
  const g = section(t)
  const e = groups.get(g) ?? [0, 0]
  e[0]++
  if (t.scope === true) e[1]++
  groups.set(g, e)
}
const reasons = new Map()
for (const t of tests) if (t.scope !== true) reasons.set(t.scope, (reasons.get(t.scope) ?? 0) + 1)
const props = Object.entries(sorted).map(([p, k]) => [p, ...['valid', 'invalid', 'computed', 'shorthand', 'inherits'].map(x => k[x]?.length ?? 0)])
const byModule = new Map()
for (const [p, ...c] of props) {
  const m = p === '--*' ? 'css-variables-1' : module.get(p)
  const e = byModule.get(m) ?? [0, 0, 0, 0, 0, 0]
  e[0]++
  c.forEach((x, k) => e[k + 1] += x)
  byModule.set(m, e)
}
const unread = Object.entries(stats.unreadable).sort(n)
const outProps = Object.entries(stats.outProperties).sort(n)
const md = [
  `At WPT ${REVISION.slice(0, 12)}, made by import-wpt.mjs.`,
  '',
  '### Values',
  '',
  `${stats.calls} calls of the helpers read in ${fs.readdirSync(path.join(root, 'css')).length} directories of css/ `
    + `(a loop's items and a helper's calls each one); ${stats.extracted} rows for ${props.length} in-scope properties`
    + `${sorted['--*'] ? ' (--* among them)' : ''} from ${files.length} files `
    + `(${stats.duplicates} duplicates dropped), ${stats.outOfScope} calls on ${outProps.length} properties out of scope `
    + `(most: ${outProps.slice(0, 8).map(([p, c]) => `${p} ${c}`).join(', ')}), and `
    + `${unread.reduce((a, [, c]) => a + c, 0)} not read statically:`,
  '',
  table(['Why not read', 'Calls'], unread.map(([w, c]) => [w, c])),
  '',
  table(['Module', 'Properties', 'Valid', 'Invalid', 'Computed', 'Shorthand', 'Inherits'],
    [...byModule].sort((a, b) => a[0] < b[0] ? -1 : 1).map(([m, e]) => [m, ...e])),
  '',
  '### Selectors',
  '',
  report[0],
  '',
  '### Reftests',
  '',
  `${tests.length} tests (references and support files left out), ${inScope.length} in scope:`,
  '',
  table(['Suite', 'Tests', 'In scope', 'Of them Ahem', 'Of them print'], bySuite),
  '',
  table(['Out of scope because', 'Tests'], [...reasons].sort(n)),
  '',
  'By directory (CSS2: its chapters; the others: their sections, from the first `<link rel=help>`):',
  '',
  table(['Directory or section', 'Tests', 'In scope'], [...groups].sort((a, b) => a[0] < b[0] ? -1 : 1).map(([g, [all, ok]]) => [g, all, ok]))
].join('\n')
const readme = fs.readFileSync('tests/css/README.md', 'utf8')
const [before, rest] = readme.split('<!-- report -->')
const after = rest.split('<!-- /report -->')[1]
fs.writeFileSync('tests/css/README.md', `${before}<!-- report -->\n${md}\n<!-- /report -->${after}`)
console.log({values: stats.extracted, unreadable: stats.unreadable, tests: tests.length, inScope: inScope.length})

function describe(rel, text) {
  const links = [...text.matchAll(/<link\b[^>]*>/gi)].map(m => m[0])
  const attr = (tag, name) => new RegExp(`\\b${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i').exec(tag)?.slice(1).find(x => x != null)
  const rels = links.map(l => ({rel: (attr(l, 'rel') ?? '').toLowerCase(), href: attr(l, 'href')}))
  const refs = rels.filter(l => l.rel === 'match' || l.rel === 'mismatch').map(l => [resolve(rel, l.href), l.rel])
  const help = rels.filter(l => l.rel === 'help').map(l => l.href)
  const metas = [...text.matchAll(/<meta\b[^>]*>/gi)].map(m => m[0])
  const meta = name => metas.filter(m => (attr(m, 'name') ?? '').toLowerCase() === name).map(m => attr(m, 'content') ?? '')
  const flags = meta('flags').flatMap(f => f.split(/\s+/)).filter(Boolean)
  const fuzzy = meta('fuzzy')
  const script = /<script\b/i.test(text)
  const harness = /testharness\.js/.test(text)
  const name = path.basename(rel)
  const type = refs.length ? 'reftest' : harness ? 'testharness' : /-manual\./.test(name) ? 'manual'
    : /-crash\.|\/crashtests\//.test(rel) ? 'crash' : 'visual'
  const needs = [
    (flags.includes('ahem') || /\bahem\b/i.test(text)) && 'ahem', script && 'script', /-print\./.test(name) && 'print',
    /reftest-wait/.test(text) && 'wait', flags.includes('image') && 'image', (flags.includes('svg') || /\.svg$/.test(rel)) && 'svg',
    /\.(xht|xhtml|svg)$/.test(rel) && 'xml'
  ].filter(Boolean)
  for (const r of refs) {
    const file = path.join(root, r[0])
    if (!fs.existsSync(file)) continue
    const own = [...fs.readFileSync(file, 'utf8').matchAll(/<link\b[^>]*>/gi)].map(m => m[0])
      .map(l => ({rel: (attr(l, 'rel') ?? '').toLowerCase(), href: attr(l, 'href')}))
      .filter(l => l.rel === 'match' || l.rel === 'mismatch').map(l => [resolve(r[0], l.href), l.rel])
    if (own.length) r.push(own)
  }
  return {path: rel, type, refs, help, flags, fuzzy, needs}
}

function classify(t, text) {
  if (t.type === 'testharness') return 'testharness.js: needs JavaScript'
  if (t.type === 'manual') return 'interact: needs a person'
  if (t.type === 'visual') return 'visual: no reference (a golden blessed by eye could gate it)'
  for (const f of t.flags) if (FLAGS_OUT[f]) return FLAGS_OUT[f]
  if (t.needs.includes('script')) return 'script: needs JavaScript'
  for (const h of t.help) for (const [re, what] of HELP_DEFERRED) if (re.test(h)) return `deferred: ${what} (its help)`
  const css = text.replace(/<!--[\s\S]*?-->/g, '')
  for (const [re, what] of DEFERRED) if (re.test(css)) return `deferred: ${what}`
  return true
}

function section(t) {
  const parts = t.path.split('/')
  if (parts[1] === 'CSS2') return parts.length > 3 ? `CSS2/${parts[2]}` : 'CSS2 (top level)'
  const h = t.help.find(h => /csswg|w3\.org/.test(h))
  const anchor = h?.split('#')[1]
  return `${parts[1]}${anchor ? ' #' + anchor : ' (no section)'}`
}

function resolve(from, href) {
  if (!href) return null
  if (href.startsWith('/')) return href.slice(1)
  return path.posix.normalize(path.posix.join(path.posix.dirname(from), href))
}

function scripts(html) {
  return [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)]
    .filter(m => !/\bsrc\s*=/.test(m[1])).map(m => m[2].replace(/^\s*<!\[CDATA\[|\]\]>\s*$/g, ''))
}

function* walk(dir) {
  for (const e of fs.readdirSync(dir, {withFileTypes: true}).sort((a, b) => a.name < b.name ? -1 : 1)) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) yield* walk(p)
    else yield p
  }
}

// (one row a line: diffs stay readable, the file small)
function writeJson(file, data, depth) {
  const rows = (v, d) => {
    if (d <= 0 || v == null || typeof v !== 'object') return JSON.stringify(v)
    const pad = '  '.repeat(depth - d + 1), end = '  '.repeat(depth - d)
    if (Array.isArray(v)) return v.length ? `[\n${v.map(x => pad + rows(x, d - 1)).join(',\n')}\n${end}]` : '[]'
    const ks = Object.keys(v)
    return ks.length ? `{\n${ks.map(k => `${pad}${JSON.stringify(k)}: ${rows(v[k], d - 1)}`).join(',\n')}\n${end}}` : '{}'
  }
  fs.writeFileSync(file, rows(data, depth) + '\n')
}

function sh(cmd, args) {
  const r = spawnSync(cmd, args, {encoding: 'utf8', maxBuffer: 1 << 28})
  if (r.status !== 0) throw Error(`${cmd}: ${r.stderr}`)
  return r.stdout
}
