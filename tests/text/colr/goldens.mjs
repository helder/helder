// Chromium's drawings of the COLR v1 fixtures (ColorGlyphs.test.hx's
// goldens): each glyph of glyphs.json in a cell of a sheet, by Canvas 2D's
// fillText (Skia's COLR v1), in black on white. Run from the repository's
// root with Playwright (bun add --no-save playwright@1.56.1):
//
//   node tests/text/colr/goldens.mjs
import fs from 'node:fs'
import {chromium} from 'playwright'

const D = 'tests/text/colr/'
const CELL = 64, SIZE = 48, COLUMNS = 20
const glyphs = JSON.parse(fs.readFileSync(D + 'glyphs.json', 'utf8'))
const browser = await chromium.launch()
const page = await browser.newPage()
for (const [name, file] of [['test_glyphs', 'test_glyphs-glyf_colr_1.ttf'], ['noto', 'noto-colrv1-subset.ttf']]) {
  const list = glyphs[name], rows = Math.ceil(list.length / COLUMNS)
  const font = fs.readFileSync(D + file).toString('base64')
  const png = await page.evaluate(async ({font, list, rows, CELL, SIZE, COLUMNS}) => {
    const face = new FontFace('t', `url(data:font/ttf;base64,${font})`)
    document.fonts.add(await face.load())
    const c = document.createElement('canvas')
    c.width = CELL * COLUMNS
    c.height = CELL * rows
    const ctx = c.getContext('2d')
    ctx.fillStyle = '#fff'
    ctx.fillRect(0, 0, c.width, c.height)
    ctx.fillStyle = '#000'
    ctx.font = `${SIZE}px t`
    list.forEach((g, i) => ctx.fillText(String.fromCodePoint(g.cp), (i % COLUMNS) * CELL + 8, Math.floor(i / COLUMNS) * CELL + 56))
    return c.toDataURL('image/png')
  }, {font, list, rows, CELL, SIZE, COLUMNS})
  fs.writeFileSync(D + name + '.png', Buffer.from(png.split(',')[1], 'base64'))
  console.log(D + name + '.png', list.length, 'glyphs')
}
await browser.close()
