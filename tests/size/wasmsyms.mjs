const names = [
  'custom', 'type', 'import', 'function', 'table', 'memory', 'global',
  'export', 'start', 'element', 'code', 'data', 'data count', 'tag'
]

function reader(buf) {
  let pos = 0
  function take(n) {
    if (pos + n > buf.length) throw new Error('truncated wasm section')
    const bytes = buf.subarray(pos, pos + n)
    pos += n
    return bytes
  }
  function byte() {
    return take(1)[0]
  }
  function u32() {
    let n = 0
    for (let shift = 0; shift <= 28; shift += 7) {
      const b = byte()
      if (shift === 28 && b > 15) throw new Error('invalid wasm u32')
      n += (b & 127) * 2 ** shift
      if (b < 128) return n
    }
  }
  return { take, byte, u32, str: () => take(u32()).toString('utf8'), more: () => pos < buf.length }
}

function functionImports(r) {
  let count = 0
  for (let n = r.u32(); n > 0; n--) {
    r.str()
    r.str()
    const kind = r.byte()
    if (kind === 0) {
      count++
      r.u32()
    } else if (kind === 1 || kind === 2) {
      if (kind === 1) valueType(r)
      const flags = r.u32()
      r.u32()
      if (flags & 1) r.u32()
    } else if (kind === 3) {
      valueType(r)
      r.byte()
    } else if (kind === 4) {
      r.byte()
      r.u32()
    } else throw new Error(`unknown wasm import kind ${kind}`)
  }
  return count
}

function valueType(r) {
  const type = r.byte()
  if (type === 0x63 || type === 0x64) r.u32()
}

export function wasm(buf) {
  const r = reader(buf)
  if (r.take(8).toString('hex') !== '0061736d01000000') throw new Error('invalid wasm header')
  const sections = []
  const functions = new Map()
  const bodies = []
  let imports = 0
  while (r.more()) {
    const id = r.byte()
    const bytes = r.u32()
    const section = reader(r.take(bytes))
    const name = id === 0 ? section.str() : names[id] ?? `section ${id}`
    const kind = id === 10 ? 'code' : id === 11 ? 'data' : null
    sections.push({ name: id === 0 ? `custom: ${name}` : name, bytes, kind })
    if (id === 2) imports = functionImports(section)
    if (id === 10) {
      for (let n = section.u32(); n > 0; n--) {
        const size = section.u32()
        bodies.push(size)
        section.take(size)
      }
    }
    if (id === 0 && name === 'name') {
      while (section.more()) {
        const kind = section.byte()
        const part = reader(section.take(section.u32()))
        if (kind !== 1) continue
        for (let n = part.u32(); n > 0; n--) functions.set(part.u32(), part.str())
      }
    }
  }
  // Body indices omit imports. Wasm stores constants and mutable bytes in the same data section.
  const symbols = bodies.map((bytes, i) => ({ name: functions.get(imports + i), bytes }))
  return { sections, symbols }
}
