// toFixed, toPrecision and toExponential of random doubles, node the
// oracle: the exact value's digits, ties up (dyadic halfway cases: 0.125,
// 2.5), around 2^53, 2^63 and 1e21, subnormals, every digit count to 100.
let seed = 0x2545f491
function next(): number {
  seed ^= seed << 13
  seed ^= seed >>> 17
  seed ^= seed << 5
  return seed >>> 0
}
const words = new Uint32Array(2), view = new Float64Array(words.buffer)
function bits(high: number, low: number): number {
  words[0] = low
  words[1] = high
  return view[0]
}
// (a random mantissa at a binary exponent from low to high)
function near(low: number, high: number): number {
  const e = low + next() % (high - low + 1)
  return bits(((e + 1023) << 20) | (next() & 0xfffff) | (next() & 1 ? 0x80000000 : 0), next())
}
const values: number[] = [0, -0, NaN, Infinity, -Infinity, 5e-324, -5e-324, 2.2250738585072014e-308, 1.7976931348623157e308, 1e21, -1e21, 999999999999999900000, 1e21 - 65536, 2 ** 53, 2 ** 53 - 1, 2 ** 53 + 2, 2 ** 63, 2 ** 63 - 1024, 2 ** 64, 2 ** 70, 0.5, 1.5, 2.5, -2.5, 0.125, 0.375, -0.375, 1.005, 1.45, 8.345, 1.0000000000000002, 0.1, 0.2, 0.3, 1e-7, -1e-7, 123.456, 0.000001, 99.99, 9.995, 0.05, 0.015, 1e-20, 1e-30, 4.35, 1.255]
for (let i = 0; i < 300; i++) {
  const x = bits(next() | 0, next())
  if (Number.isFinite(x)) values.push(x)
}
for (let i = 0; i < 1200; i++) values.push(near(-80, 72))
for (let i = 0; i < 300; i++) values.push(near(-1074, -900))
// (halfway at some digit count: an odd numerator over a power of two)
for (let i = 0; i < 400; i++) values.push(((next() % 1048576) * 2 + 1) / 2 ** (1 + next() % 40))
for (let i = 0; i < 300; i++) values.push((next() % 10000000) / 10 ** (next() % 9))
const lines: string[] = []
for (const x of values) {
  const f = [next() % 4, next() % 21, next() % 101]
  const p = [1 + next() % 21, 1 + next() % 100]
  lines.push([...f.map(d => x.toFixed(d)), ...p.map(d => x.toPrecision(d)), ...f.map(d => x.toExponential(d))].join(' '))
}
console.log(values.length)
for (const line of lines) console.log(line)
let all = ''
for (let d = 0; d <= 100; d++) all += (0.1).toFixed(d) + (2 ** -60).toFixed(d) + (123456789.123).toFixed(d) + (2 ** 69).toFixed(d)
console.log(all.length, all.slice(-400))
