// The site's pictures (bun run site:visuals): frames of the examples taken
// headless (helder run --headless --snap), so the docs' and the landing's
// pictures are what the programs draw today. Written to site/visuals/ as
// WebP (cwebp, else the PNG) and committed: small, and the site's build
// stays quick. Run it again when an example's look changes.
//
//   node site/visuals.mjs [ids...]      (default: every one)
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
process.chdir(root)
const out = 'site/visuals'
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'helder-visuals-'))

// each: the program, its size in points, when, a script driving it (steps inline)
export const VISUALS = [
  { id: 'notes', entry: 'examples/notes', size: '1280x720', at: '1.5' },
  { id: 'mail', entry: 'examples/mail', size: '860x560' },
  { id: 'services', entry: 'docs/examples/services', script: [{ t: 0.3, type: 'tap', label: 'de-DE' }] },
  { id: 'todo', entry: 'examples/ts-todo', size: '480x560', at: 'end',
    script: [{ t: 0.2, type: 'tap', role: 'textbox' }, { t: 0.3, type: 'type', text: 'Ship the docs', every: 0.03 },
      { t: 1, type: 'key', name: 'Enter' }, { t: 1.3, type: 'mark', name: 'end' }] },
  { id: 'canvas', entry: 'examples/canvas-window', at: '0.5' },
  { id: 'palette', entry: 'examples/ts-palette' },
  { id: 'falling', entry: 'examples/falling', at: '2.5' },
  { id: 'lights', entry: 'docs/examples/scene-lights', at: '1' }
]

// the commands of `helder help`, each its first clause: the CLI page's terminal
function help() {
  const r = spawnSync(process.execPath, ['src/helder/cli/run.mjs', 'help'], { encoding: 'utf8' })
  const text = r.stdout.replace(/\x1b\[[0-9;]*m/g, '')
  const rows = text.slice(text.indexOf('commands:')).split('\n').slice(1).filter(l => /^  \w/.test(l)).map(l => {
    const [, name, about] = /^  (\w+)\s+(.*)$/.exec(l)
    return `  ${name.padEnd(9)}${about.split(/ \(|: |; /)[0]}`
  })
  fs.writeFileSync(`${out}/help.txt`, rows.join('\n') + '\n')
  console.log(`${out}/help.txt`)
}

const only = process.argv.slice(2)
const webp = spawnSync('cwebp', ['-version']).status === 0
fs.mkdirSync(out, { recursive: true })
if (!only.length || only.includes('help')) help()
let failed = 0
try {
  for (const v of VISUALS.filter(v => !only.length || only.includes(v.id))) {
    const png = path.join(tmp, v.id + '.png')
    const args = ['src/helder/cli/run.mjs', 'run', '--headless', v.entry, '--snap', png, '--scale', '2']
    if (v.size) args.push('--size', v.size)
    if (v.at) args.push('--at', v.at)
    if (v.script) {
      fs.writeFileSync(path.join(tmp, v.id + '.json'), JSON.stringify(v.script))
      args.push('--script', path.join(tmp, v.id + '.json'))
    }
    const r = spawnSync(process.execPath, args, { encoding: 'utf8' })
    if (r.status !== 0 || !fs.existsSync(png)) {
      console.error(`${v.id}: failed\n${(r.stdout + r.stderr).slice(-1500)}`)
      failed++
      continue
    }
    for (const f of [`${out}/${v.id}.webp`, `${out}/${v.id}.png`]) fs.rmSync(f, { force: true })
    const file = webp ? `${out}/${v.id}.webp` : `${out}/${v.id}.png`
    // (at most 1600 pixels wide: twice the docs' column)
    const wide = fs.readFileSync(png).readUInt32BE(16) > 1600
    if (webp) spawnSync('cwebp', ['-quiet', '-q', '86', ...(wide ? ['-resize', '1600', '0'] : []), png, '-o', file])
    else fs.copyFileSync(png, file)
    console.log(`${file.padEnd(32)} ${(fs.statSync(file).size / 1024).toFixed(0)} KB`)
  }
} finally {
  fs.rmSync(tmp, { recursive: true, force: true })
}
if (failed) process.exit(1)
