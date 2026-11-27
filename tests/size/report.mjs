import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { measure, owner } from './syms.mjs'

const dir = 'tests/size/baselines'
const out = 'bin/size'
const [host, only] = process.argv.slice(2)
const os = host?.split('-')[0]
if (!['macos', 'linux'].includes(os)) throw new Error('expected a macOS or Linux host target')
const programs = JSON.parse(readFileSync('tests/size/programs.json', 'utf8'))
  .map(p => p.name).filter(p => !only || p === only)
if (programs.length === 0) throw new Error(`unknown size program ${only}`)
const bless = Boolean(process.env.BLESS)
const targets = [
  { target: host, baseline: `${dir}/${host}.json`, ext: '' },
  { target: 'wasm32-wasi', baseline: `${dir}/${os}-wasm32-wasi.json`, ext: '.wasm' }
]
const metrics = ['total', 'code', 'const', 'data']

function add(map, name, bytes) {
  map.set(name, (map.get(name) ?? 0) + bytes)
}

function group(symbols) {
  const packages = new Map()
  const classes = new Map()
  for (const { name, bytes } of symbols) {
    const { pkg, cls } = owner(name)
    add(packages, pkg, bytes)
    if (cls) add(classes, cls, bytes)
  }
  return { packages: Object.fromEntries([...packages].sort()), classes: [...classes] }
}

function compare(now, before = {}) {
  return [...new Set([...Object.keys(now), ...Object.keys(before)])]
    .map(name => [name, now[name] ?? 0, before[name] ?? 0])
    .sort((a, b) => (b[1] - b[2]) - (a[1] - a[2]) || b[1] - a[1] || a[0].localeCompare(b[0]))
}

const fmt = n => n.toLocaleString('en-US')
const delta = n => n > 0 ? `+${fmt(n)}` : fmt(n)
const label = name => name.replaceAll('|', '\\|')
const row = ([name, now, old], base) =>
  `| ${label(name)} | ${fmt(now)} | ${base ? fmt(old) : '—'} | ${base ? delta(now - old) : '—'} |`
const table = (title, rows, align) => [title, align, ...rows, '']
const diffTable = (title, rows, base) => table(`| ${title} | Bytes | Baseline | Change |`,
  rows.map(r => row(r, base)), '| --- | ---: | ---: | ---: |')

const md = [
  '# Binary size report', '',
  `Host: ${host}. Release builds with full DCE and symbols. All sizes are bytes.`, '',
  'The gate allows 2% or 32 KiB of growth per file, whichever is larger.',
  'Package and class sizes cover symbol-attributed code. Section sizes exclude zero-fill.',
  'Mach-O symbol sizes use address gaps. Wasm constants are included in the data section.', ''
]

function check(program, { target, ext, baseline }, before) {
  if (before && (!metrics.every(k => Number.isSafeInteger(before[k]) && before[k] >= 0) ||
      !before.packages || !Object.values(before.packages).every(n => Number.isSafeInteger(n) && n >= 0))) {
    throw new Error(`invalid baseline for ${program} in ${baseline}`)
  }
  const { sizes, sections, symbols } = measure(`${out}/${program}${ext}`, target)
  const { packages, classes } = group(symbols)
  const growth = before ? sizes.total - before.total : 0
  const limit = before ? Math.floor(Math.max(before.total * 0.02, 32 * 1024)) : 0
  const ok = before && growth <= limit
  const status = !before ? 'no baseline' : ok ? 'pass' : `regression (limit +${fmt(limit)} bytes)`
  const changes = compare(packages, before?.packages)
  const title = `${program} / ${target}`
  const verdict = before ? `${delta(growth)} bytes, ${status}` : status
  console.log(`${title}: ${fmt(sizes.total)} bytes (${verdict})`)
  if (before) {
    const grew = changes.filter(([, now, old]) => now > old).slice(0, 5)
    if (grew.length) console.log('  Package growth: ' + grew.map(([p, now, old]) => `${p} ${delta(now - old)} B`).join(', '))
    if (!bless && growth < 0) console.log(`  Run BLESS=1 bun run test size ${program} to record the smaller size`)
  } else if (!bless) console.error(`  Missing ${baseline} entry for ${program}. Run BLESS=1 bun run test size ${program}`)

  md.push(`## ${title}`, '', `**${status}${bless ? ' · blessed' : ''}**`, '')
  md.push(...diffTable('Metric', metrics.map(k => [k, sizes[k], before?.[k]]), before))
  md.push('### Code by package', '', ...diffTable('Package', changes, before))
  md.push('### Largest 20 classes by code size', '', ...table('| Class | Bytes |',
    classes.sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, 20)
      .map(([name, bytes]) => `| ${label(name)} | ${fmt(bytes)} |`), '| --- | ---: |'))
  md.push('### File-backed sections', '', ...table('| Section | Bytes |',
    sections.filter(s => s.bytes > 0).sort((a, b) => b.bytes - a.bytes)
      .map(s => `| ${label(s.name)} | ${fmt(s.bytes)} |`), '| --- | ---: |'))
  return { ok, sizes: { ...sizes, packages } }
}

const updates = targets.map(spec => ({
  ...spec, programs: existsSync(spec.baseline) ? JSON.parse(readFileSync(spec.baseline, 'utf8')) : {}
}))
let ok = true
for (const program of programs) {
  for (const spec of updates) {
    const result = check(program, spec, spec.programs[program])
    if (!result.ok) ok = false
    spec.programs[program] = result.sizes
  }
}
writeFileSync(`${out}/report.md`, md.join('\n'))
console.log(`${out}/report.md`)
if (bless) {
  mkdirSync(dir, { recursive: true })
  for (const { baseline, programs } of updates) {
    const tmp = `${baseline}.${process.pid}.tmp`
    writeFileSync(tmp, JSON.stringify(programs, null, 2) + '\n')
    renameSync(tmp, baseline)
    console.log(`Blessed ${baseline}`)
  }
} else if (!ok) process.exitCode = 1
