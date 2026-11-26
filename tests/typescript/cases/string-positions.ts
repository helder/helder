// String's position methods past either end: undefined, NaN or "" as
// JavaScript's (codePointAt's undefined once read as 0), typed and dynamic,
// and a surrogate pair's code point.
const e = '', s = 'a😀b'
const d: any = s
console.log(e.codePointAt(3) ?? -1, s.codePointAt(9) ?? -1, s.codePointAt(-1) ?? -1, d.codePointAt(4) ?? -1)
const a = e.codePointAt(3)
console.log(a, typeof a, s.codePointAt(1), s.codePointAt(2), s.codePointAt(0), d.codePointAt(3))
console.log(s.at(-1), s.at(9), s.at(-9), e.charAt(2) === '', s.charCodeAt(9), d.charCodeAt(1), s.charAt(-1) === '')
const xs = [0, 1, 2, 3, 4, -1].map(i => s.codePointAt(i))
console.log(xs, xs.map(x => x === undefined))
