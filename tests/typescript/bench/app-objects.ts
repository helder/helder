// App-style objects: rows filtered, mapped to spread copies, sorted by a
// comparator with localeCompare, grouped in a Map and partly stringified.
type Row = {id: number, name: string, score: number, tags: string[]}
function make(n: number): Row[] {
  const rows: Row[] = []
  for (let i = 0; i < n; i++) rows.push({id: i, name: 'row ' + (i * 7919 % 1000), score: (i * 31) % 97, tags: i % 3 ? ['a', 'b'] : ['c']})
  return rows
}
let total = 0
for (let r = 0; r < 20; r++) {
  const rows = make(20000)
  const kept = rows.filter(x => x.score > 40 && x.tags.includes('a')).map(x => ({...x, label: x.name.toUpperCase() + '#' + x.id}))
  kept.sort((a, b) => a.score - b.score || a.name.localeCompare(b.name))
  const byName = new Map<string, number>()
  for (const k of kept) byName.set(k.name, (byName.get(k.name) ?? 0) + k.score)
  total += kept.length + byName.size + JSON.stringify(kept.slice(0, 200)).length
}
console.log(total)
