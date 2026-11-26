// Searches the matcher skips start positions for (the units a match starts
// with, a line's start) and one matcher kept across exec calls: each pattern
// over random texts with exec loops, test, match, split, replace and sticky.
const patterns: RegExp[] = [/a/g, /ab+c/g, /[b-d]x?/g, /k/gi, /K[a-c]/gi, /é/gi, /^a.*$/gm, /^b/g, /^(?:c|d)/gm, /(a|bc|d)+/g,
  /x*/g, /(?<=a)b/g, /(?<!a)b/g, /(?=c)c./g, /\bab/g, /(\w)\1/g, /[^a]b/g, /a{2,3}/g, /(?<w>[a-c]+)-\k<w>/g, /[\u{1F600}-\u{1F64F}]/gu,
  /\u{1F600}a/gu, /ab/y, /./gs, /[a-z]+/gi, /(?:)/g, /$/gm, /\n^/gm, /[À-ÿ]/g, /\d+/g, /c?d/g]
const alphabet = ['a', 'b', 'c', 'd', 'x', 'k', 'K', 'é', 'É', '\n', ' ', '-', '1', '2', 'A', 'B', '😀', 'ÿ']
let seed = 11
function rnd(n: number): number {
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed % n
}
const texts: string[] = ['', 'a', 'abc-abc', 'kK', 'line a\nline b\na last', '😀a😀b']
for (let i = 0; i < 40; i++) {
  let t = ''
  const n = rnd(24)
  for (let j = 0; j < n; j++) t += alphabet[rnd(alphabet.length)]
  texts.push(t)
}
let h = 0
function mix(s: string) {
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 1000000007
}
for (const re of patterns) {
  const out: string[] = []
  for (const t of texts) {
    const r = new RegExp(re.source, re.flags)
    const found: string[] = []
    let m: RegExpExecArray | null
    for (let guard = 0; guard < 100 && (m = r.exec(t)) !== null; guard++) {
      found.push(m.index + ':' + m[0] + (m.length > 1 ? '(' + m.slice(1).join('|') + ')' : '') + (m.groups ? JSON.stringify(m.groups) : ''))
      if (!r.global && !r.sticky) break
      if (m[0] === '') r.lastIndex++
    }
    out.push(found.join(','), String(re.test(t)), JSON.stringify(t.match(re)), JSON.stringify(t.split(re)), t.replace(re, (s: string) => '<' + s + '>'), t.replace(re, '[$&]'))
  }
  mix(out.join('\n'))
  console.log(re.source, re.flags, out.slice(0, 6 * 6).join(' / ').length)
}
console.log(h)
const log = 'one\ntwo three\nfour'
const re = /^\w+/gm
console.log(log.match(re), re.exec(log), re.lastIndex, re.exec('xx'), re.lastIndex, re.exec(log)?.index)
