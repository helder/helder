// fuzz (seed 500, program 47): with the u (or v) flag a lastIndex inside a
// surrogate pair is the pair's: the match starts at the code point holding it
const s = '😀a😀b'
for (const flags of ['gu', 'yu', 'g', 'y', 'gv']) {
  const re = new RegExp('.', flags + 's')
  const out: Array<number | string> = []
  for (const at of [1, 3, 4, 5]) {
    re.lastIndex = at
    const m = re.exec(s)
    out.push(m === null ? -1 : m.index, m === null ? '' : m[0].length, re.lastIndex)
  }
  console.log(flags, out.join(' '))
}
const sticky = /😀/uy
sticky.lastIndex = 1
console.log(sticky.test('😀'), sticky.lastIndex)
