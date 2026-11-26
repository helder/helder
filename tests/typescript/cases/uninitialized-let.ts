// A let of a typed slot declared without a value, written before it is
// read (TypeScript's definite assignment): no undefined checked into it
let a: number
a = 1
let flag: boolean, text: string
flag = a > 0
text = flag ? 'yes' : 'no'
function sign(k: number): string {
  let s: string
  if (k > 0) s = 'pos'
  else if (k < 0) s = 'neg'
  else s = 'zero'
  return s
}
let q: number, w: number
;[q, w] = [3, 4]
console.log(a, flag, text, sign(1), sign(-1), sign(0), q + w)
for (let i = 0; i < 3; i++) {
  let x: number
  x = i * 2
  console.log(x)
}
