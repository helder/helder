// fuzz (seed 200, programs 8 and 53): a number array's element at a loop
// counter (an Int64) given a value that is no number by a compound
// assignment (Math.max() of nothing: a call the runtime makes) failed to
// build (TSHXIR003: expected TF64, got TI64)
function f(): number[] {
  const v: number[] = [1, 2, 3]
  for (let i = 0; i < v.length; i++) {
    v[i] += Math.max()
    if (i > 0) v[i] -= Math.min()
  }
  return v
}
console.log(f())
