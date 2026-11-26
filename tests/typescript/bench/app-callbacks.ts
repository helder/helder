// App-style callbacks: array methods with lambdas, reduce, sort comparators,
// closures made and called, functions composed.
type P = {x: number, y: number, kind: string}
function counter() {
  let n = 0
  return {next: () => ++n, get: () => n}
}
function compose<A, B, C>(f: (a: A) => B, g: (b: B) => C): (a: A) => C {
  return a => g(f(a))
}
let total = 0
for (let r = 0; r < 30; r++) {
  const ps: P[] = Array.from({length: 5000}, (_, i) => ({x: i % 113, y: (i * 7) % 89, kind: i % 4 === 0 ? 'big' : 'small'}))
  const c = counter()
  const scaled = ps.map(p => ({...p, x: p.x * 2})).filter(p => p.kind === 'small' || c.next() > 0)
  const sum = scaled.reduce((acc, p) => acc + p.x + p.y, 0)
  const sorted = [...scaled].sort((a, b) => a.x - b.x || b.y - a.y)
  const f = compose((p: P) => p.x + p.y, (n: number) => n * 3)
  const firstBig = sorted.find(p => p.kind === 'big')
  const anyNeg = sorted.some(p => p.x < 0), allSmall = sorted.every(p => p.y < 89)
  const idx = sorted.findIndex(p => f(p) > 300)
  const flat = ps.slice(0, 500).flatMap(p => [p.x, p.y]).filter(n => n % 2 === 0)
  let fsum = 0
  sorted.forEach(p => { fsum += f(p) })
  total += sum + c.get() + (firstBig ? firstBig.x : 0) + (anyNeg ? 1 : 0) + (allSmall ? 1 : 0) + idx + flat.length + fsum % 1000
}
console.log(total)
