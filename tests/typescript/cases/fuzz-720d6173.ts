// fuzz (seed 1, program 1): unary + and - are ToNumber, of a string or a
// boolean too, not its reference read as a double
const s: string = 'x'
const a: number[] = [(+"abcabc-12.5e-1"), +s, -s, +' 12 ', -'0', +'', +'1e3']
console.log(a, Object.is(a[4], -0))
const flags: number[] = [+true, -false, +(s === 'x'), -(s === 'y')]
console.log(flags, Object.is(flags[3], -0))
for (let i = 0; i < 2; i++) console.log(+('7' + i), -(i + 'z'))
