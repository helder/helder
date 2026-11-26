// Templates and chains of + joined at once: each piece's text taken where
// its own + would (the first two after both are evaluated, the others right
// after their own), an object by valueOf for + and by toString in a
// template, later writes not seen by earlier pieces, numbers before the
// first string added as numbers.
let a = 'x'
console.log(a + (a = 'z'), `${a}${a = 'q'}${a}`)
let n = 1
console.log(n + (n = 5), 'k' + n + (n = 7) + n)
let g = 'g'
const h = () => { g = 'G'; return '!' }
console.log(g + 1 + g + h() + g, `${g}-${h()}-${g}`)
function f(s: string, x: number, o: unknown) {
  let t = s
  const k = () => { t = 'T'; return 'k' }
  return t + x + t + k() + t + o + `${t}${o}${x}` + ''
}
console.log(f('s', 1.5, {toString() { return 'o' }}), f('', -0, null), f('', NaN, undefined))
const parts: string[] = ['a', 'b']
console.log(parts[0] + parts[1] + parts.length + true + null + undefined + [1, 2] + {} + 0.1)
console.log(`${1}${2}` + 3 + 4, 1 + 2 + `${3}` + 4 + 5, `` + ``, `${''}`, `${-0}|${2 ** 31}|${1e21}`)
const o = {valueOf() { return 1 }, toString() { return 's' }}
const s: string = 'a'
console.log(s + o, `${o}`, o + s, s + o + o, 1 + 2 + s + 1 + 2)
let c = 'c'
c += o
c += 'd' + o + `${o}`
console.log(c)
const order: string[] = []
const t = (x: string) => { order.push(x); return x }
const p = {valueOf() { order.push('vp'); return 'P' }, toString() { order.push('tp'); return 'p' }}
console.log(t('a') + p + t('b') + (order.push('c'), 'c') + `${p}${t('d')}`, order.join())
try {
  console.log('x' + t('e') + (Symbol('y') as any))
} catch (e) {
  console.log((e as Error).name, order.join())
}
const long = (i: number) => 'i' + i + ',' + (i * 2) + ',' + (i + 0.5) + ',' + `${i}` + '/' + i.toFixed(2) + ';' + (i % 3 === 0 ? 'fizz' : '') + '.'
let all = ''
for (let i = 0; i < 20; i++) all += long(i)
console.log(all)
let built = ''
for (let i = 0; i < 3; i++) built += o
console.log(built)
