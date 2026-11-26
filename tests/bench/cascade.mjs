// helder.css's cascade on the HTML Standard as one page (bench cascade): the
// page (the html bench's input) and its style sheets fetched into
// bin/bench/html, then CascadeBench run natively on them (bench layout:
// LayoutBench, the same arguments).
//
//   node tests/bench/cascade.mjs bin/bench/CascadeBench
import fs from 'node:fs'
import {execFileSync} from 'node:child_process'

const [bench] = process.argv.slice(2)
const dir = 'bin/bench/html'
fs.mkdirSync(dir, {recursive: true})
const page = `${dir}/html-spec.html`
async function fetchTo(url, file) {
  if (fs.existsSync(file)) return
  const res = await fetch(url, {headers: {'user-agent': 'helder-bench'}})
  if (!res.ok) throw new Error(`${url}: ${res.status}`)
  fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()))
}
await fetchTo('https://html.spec.whatwg.org/', page)
// (its <link rel=stylesheet>s, by URL, for the bench's loader)
const sheets = {}
for (const m of fs.readFileSync(page, 'utf8').matchAll(/<link[^>]*rel="?stylesheet"?[^>]*href="([^"]+)"/g)) {
  const file = `${dir}/sheet-${Object.keys(sheets).length}.css`
  await fetchTo(m[1], file)
  sheets[m[1]] = file
}
fs.writeFileSync(`${dir}/sheets.json`, JSON.stringify(sheets, null, 2))
process.stdout.write(execFileSync(bench, [page, `${dir}/sheets.json`, process.env.RUNS ?? '3'], {encoding: 'utf8', maxBuffer: 1 << 26}))
