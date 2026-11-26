// fuzz: seed 32921, program 101, case 31 (json): mismatch
function show(v: unknown, d: number = 0): string {
  if (typeof v === 'number') return Object.is(v, -0) ? '-0' : String(v)
  if (typeof v === 'string') return JSON.stringify(v)
  if (typeof v === 'function') return 'fn ' + v.name
  if (typeof v === 'symbol') return v.toString()
  if (typeof v !== 'object' || v === null) return String(v)
  if (d > 3) return '..'
  if (Array.isArray(v)) {
    const items: string[] = []
    for (let i = 0; i < v.length; i++) items.push(i in v ? show(v[i], d + 1) : '_')
    return '[' + items.join(', ') + ']'
  }
  if (v instanceof Error) return v.name + ': ' + v.message
  const proto = Object.getPrototypeOf(v)
  const name: string = proto === null ? 'null' : proto === Object.prototype ? '' : String(proto.constructor?.name)
  const items: string[] = []
  for (const [k, x] of Object.entries(v)) items.push(k + ': ' + show(x, d + 1))
  return name + '{' + items.join(', ') + '}'
}
function p(v: unknown): void {
  console.log(show(v))
}
function c0(): void {
  p(JSON.parse("[1e400,-0,0.1,1e21,12345678901234567890]"))
  p(JSON.parse("\"\\u00e9\\ud83d\\ude00\""))
  for (let i1 = 0; i1 < 6; i1 += 2) {}
}
c0()
export {}
