import { execFileSync } from 'node:child_process'
import { readFileSync, statSync } from 'node:fs'
import { wasm } from './wasmsyms.mjs'

function lines(cmd, args) {
  const env = { ...process.env, LC_ALL: 'C' }
  return execFileSync(cmd, args, { env, encoding: 'utf8', maxBuffer: 32 * 1024 ** 2 }).split('\n')
}

function mach(file) {
  const sections = []
  let segment
  for (const line of lines('size', ['-m', '-l', file])) {
    const seg = /^Segment (\S+):/.exec(line)
    if (seg) segment = seg[1]
    const m = /^\s+Section (\S+): (\d+) \(addr (0x[\da-f]+) offset \d+\)/i.exec(line)
    if (!m) continue
    const [, name, bytes, at] = m
    let kind = null
    if (segment === '__TEXT' && /^__(text|stubs|stub_helper|auth_stubs)$/.test(name)) kind = 'code'
    else if (segment === '__DATA_CONST' || /^__(const|cstring|literal\d+)$/.test(name)) kind = 'const'
    else if (segment.startsWith('__DATA')) kind = 'data'
    sections.push({ name: `${segment},${name}`, bytes: Number(bytes), at: Number(at), kind })
  }
  const text = sections.find(s => s.name === '__TEXT,__text')
  if (!text) throw new Error(`no Mach-O __text section in ${file}`)
  const end = text.at + text.bytes
  const at = new Map()
  for (const line of lines('nm', ['-n', '-m', file])) {
    const m = /^([\da-f]+) \(__TEXT,__text\) .*? (\S+)$/.exec(line)
    if (!m) continue
    const addr = parseInt(m[1], 16)
    const name = m[2].replace(/^_/, '')
    if (addr >= text.at && addr < end && (!at.has(addr) || owner(name).cls)) at.set(addr, name)
  }
  // Mach-O's nm reports addresses alone. Estimate lengths up to the next distinct address.
  const entries = [...at.entries()]
  const symbols = entries.map(([addr, name], i) => ({ name, bytes: (entries[i + 1]?.[0] ?? end) - addr }))
  return { sections, symbols }
}

function elf(file) {
  const sections = []
  for (const line of lines('readelf', ['-W', '-S', file])) {
    const m = /^\s*\[\s*\d+\]\s+(\S+)\s+(\S+)\s+([\da-f]+)\s+[\da-f]+\s+([\da-f]+)\s+[\da-f]+\s+([A-Z]*)\s+\d+\s+\d+\s+\d+\s*$/i.exec(line)
    if (!m || m[2] === 'NOBITS') continue
    const [, name, , at, bytes, flags] = m
    let kind = null
    if (flags.includes('X')) kind = 'code'
    else if (/^\.(s?rodata|data\.rel\.ro)(\.|$)/.test(name)) kind = 'const'
    else if (flags.includes('A') && flags.includes('W')) kind = 'data'
    sections.push({ name, at: parseInt(at, 16), bytes: parseInt(bytes, 16), kind })
  }
  const code = sections.filter(s => s.kind === 'code')
  if (!code.length) throw new Error(`no ELF code sections in ${file}`)
  const at = new Map()
  for (const line of lines('nm', ['-n', '-S', '--defined-only', file])) {
    const m = /^([\da-f]+) ([\da-f]+) [tTwWiI] (\S+)$/.exec(line)
    if (!m) continue
    const addr = parseInt(m[1], 16)
    const bytes = parseInt(m[2], 16)
    const name = m[3]
    if (bytes > 0 && code.some(s => addr >= s.at && addr + bytes <= s.at + s.bytes) &&
        (!at.has(addr) || owner(name).cls)) at.set(addr, { name, bytes })
  }
  // Skip aliases and clip overlapping ranges to count each code byte once.
  const entries = [...at.entries()]
  const symbols = entries.map(([addr, { name, bytes }], i) => ({
    name, bytes: Math.min(bytes, (entries[i + 1]?.[0] ?? Infinity) - addr)
  }))
  return { sections, symbols }
}

export function measure(file, target) {
  const total = statSync(file).size
  const { sections, symbols } = target === 'wasm32-wasi' ? wasm(readFileSync(file))
    : target.startsWith('macos-') ? mach(file) : elf(file)
  const sizes = { total, code: 0, const: 0, data: 0 }
  for (const { kind, bytes } of sections) if (kind) sizes[kind] += bytes
  if (!symbols.some(s => s.bytes > 0 && owner(s.name).cls)) throw new Error(`no hxmc function symbols in ${file}`)
  return { sizes, sections, symbols }
}

export function owner(name) {
  // hxmc names private types F_package__Module_Type_method.
  const m = /^[FMSCVIDG]_((?:[a-z0-9][a-z0-9]*_)*)(_?[A-Z][^_]*)(?:_([A-Z][^_]*))?/.exec(name ?? '')
  if (!m) return { pkg: name ? '(runtime)' : '(unnamed)' }
  const [, prefix, type, nested] = m
  const pkg = prefix.slice(0, -1).replaceAll('_', '.')
  const cls = type.startsWith('_') && nested ? `${type.slice(1)}.${nested}` : type.replace(/^_/, '')
  return { pkg: pkg || '(top)', cls: pkg ? `${pkg}.${cls}` : cls }
}
