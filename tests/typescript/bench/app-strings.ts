// App-style strings: numbered words joined, split, sliced, padded and
// filtered, a regex replace over the text, a template.
let n = 0
for (let r = 0; r < 200; r++) {
  const words: string[] = []
  for (let i = 0; i < 2000; i++) words.push('word' + i)
  const text = words.join(' ')
  const parts = text.split(' ').map(w => w.slice(0, 3).padStart(5, '-')).filter(w => w.endsWith('r'))
  n += parts.length + text.replace(/o/g, '0').indexOf('w0rd99') + `${r}:${parts[0]}`.length
}
console.log(n)
