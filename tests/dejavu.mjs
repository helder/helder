// DejaVu 2.37's Serif, Sans and Sans Mono, fetched into
// bin/fonts/dejavu-2.37, not committed: the faces golden images are drawn
// with on every machine (HELDER_FONT_DIRS pointed at them), the generic
// families' in helder and in Chromium's goldens, as Ubuntu's
// fonts-dejavu-core has them
//
//   node tests/dejavu.mjs
import fs from 'node:fs'
import path from 'node:path'
import {spawnSync} from 'node:child_process'
import {createHash} from 'node:crypto'
import {fileURLToPath} from 'node:url'

export const DEJAVU = 'bin/fonts/dejavu-2.37'

export async function dejavu() {
  const dir = DEJAVU
  if (fs.existsSync(path.join(dir, 'DejaVuSansMono.ttf'))) return
  const url = 'https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.tar.bz2'
  const res = await fetch(url)
  if (!res.ok) throw Error(`${url}: ${res.status}`)
  const bytes = Buffer.from(await res.arrayBuffer())
  const sha = createHash('sha256').update(bytes).digest('hex')
  if (sha !== 'fa9ca4d13871dd122f61258a80d01751d603b4d3ee14095d65453b4e846e17d7') throw Error(`${url}: sha256 ${sha}`)
  fs.mkdirSync('bin', {recursive: true})
  const tmp = fs.mkdtempSync(path.join('bin', 'dejavu-'))
  try {
    fs.writeFileSync(path.join(tmp, 'dejavu.tar.bz2'), bytes)
    const r = spawnSync('tar', ['-xjf', path.join(tmp, 'dejavu.tar.bz2'), '-C', tmp], {encoding: 'utf8'})
    if (r.status !== 0) throw Error(`tar: ${r.stderr}`)
    fs.mkdirSync(dir, {recursive: true})
    for (const family of ['DejaVuSerif', 'DejaVuSans', 'DejaVuSansMono'])
      for (const face of ['', '-Bold', family === 'DejaVuSerif' ? '-Italic' : '-Oblique', family === 'DejaVuSerif' ? '-BoldItalic' : '-BoldOblique'])
        fs.copyFileSync(path.join(tmp, 'dejavu-fonts-ttf-2.37/ttf', family + face + '.ttf'), path.join(dir, family + face + '.ttf'))
    fs.copyFileSync(path.join(tmp, 'dejavu-fonts-ttf-2.37/LICENSE'), path.join(dir, 'LICENSE'))
  } finally {
    fs.rmSync(tmp, {recursive: true, force: true})
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await dejavu()
