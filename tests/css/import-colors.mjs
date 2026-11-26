// css-parsing-tests' colour files (CC0) as fixtures/colors, at the revision
// tests/css/manifest.json pins for its Syntax cases: <color> is the css
// lane's (CSS Color 4), not the css-syntax lane's. Run from the
// repository's root:
//   node tests/css/import-colors.mjs [checkout]   (default bin/css/css-parsing-tests, cloned if missing)
import fs from 'node:fs'
import path from 'node:path'
import {execFileSync} from 'node:child_process'

const {repository, revision} = JSON.parse(fs.readFileSync('tests/css/manifest.json', 'utf8'))
const checkout = process.argv[2] ?? 'bin/css/css-parsing-tests'
if (!fs.existsSync(checkout)) execFileSync('git', ['clone', '-q', repository, checkout], {stdio: 'inherit'})
execFileSync('git', ['-C', checkout, 'checkout', '-q', revision], {stdio: 'inherit'})
const out = 'tests/css/fixtures/colors'
fs.rmSync(out, {recursive: true, force: true})
fs.mkdirSync(out, {recursive: true})
const files = fs.readdirSync(checkout).filter(f => /^color_.*\.json$/.test(f)).sort()
for (const f of [...files, 'LICENSE']) fs.copyFileSync(path.join(checkout, f), path.join(out, f))
console.log(`${files.length} colour files from css-parsing-tests ${revision}`)
