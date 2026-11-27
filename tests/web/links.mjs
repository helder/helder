// A plain UI program links no helder.async but Errors (tests/lanes/View.hx,
// web): helder.ui and helder.view never name the rest, which is the loop's,
// its I/O and sockets; a program that does not use it neither imports
// helder_async (wasm) nor holds its classes (JavaScript). #293 and #376 (a
// call of Asset.embed: Embed.bytes links nothing) broke it unseen until the
// browser lanes could not load a page.
//
//   node tests/web/links.mjs <file.wasm | file.js>...
import fs from 'node:fs'

let failed = 0
for (const f of process.argv.slice(2)) {
  const found = f.endsWith('.wasm')
    ? [...new Set(WebAssembly.Module.imports(new WebAssembly.Module(fs.readFileSync(f))).filter(i => i.module === 'helder_async').map(i => i.name))]
    : [...new Set(fs.readFileSync(f, 'utf8').match(/helder_async_[A-Za-z0-9_]+/g) ?? [])].filter(n => !/^helder_async_Errors\b/.test(n))
  if (found.length > 0) failed++
  console.log(`links.mjs: ${f}: ${found.length == 0 ? 'ok' : 'links helder.async: ' + found.join(', ')}`)
}
if (failed > 0) process.exit(1)
