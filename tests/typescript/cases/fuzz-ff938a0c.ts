// fuzz (seed 100, program 12): Math.round of -0 is -0
const a: number = -(2 ** 31)
const r: number[] = [Math.round(a % 2), Math.round(-0), Math.round(-0.4), Math.round(-0.5), Math.round(0), Math.round(-0.6)]
console.log(r, r.map(x => Object.is(x, -0)))
