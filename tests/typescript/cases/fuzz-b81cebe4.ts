// fuzz (seed 1, program 0): a var in a for loop's head is the function's
// one binding: closures made in the loop all see its last value (a let's
// is a fresh one each iteration); at the top level too
const fs: Array<() => number> = []
for (var i = 0; i < 3; i++) fs.push(() => i * 1)
console.log(fs.map(f => f()), i)
function inner(): number[] {
  const hs: Array<() => number> = []
  for (var j = 0, m = 10; j < 3; j++, m--) hs.push(() => j * m)
  for (let k = 0; k < 3; k++) hs.push(() => k)
  return hs.map(h => h())
}
console.log(inner())
