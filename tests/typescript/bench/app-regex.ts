// App-style regular expressions: log lines parsed by an exec loop with named
// groups, replace with a function, split by a pattern, test.
const levels = ['INFO', 'WARN', 'ERROR', 'DEBUG']
const lines: string[] = []
for (let i = 0; i < 3000; i++) lines.push(`2026-11-${String(i % 28 + 1).padStart(2, '0')} ${levels[i % 4]} [svc-${i % 17}] request id=${i * 37} took ${i % 500}ms user=u${i % 91}`)
const log = lines.join('\n')
let total = 0
for (let r = 0; r < 10; r++) {
  const re = /^(?<date>\d{4}-\d\d-\d\d) (?<level>[A-Z]+) \[(?<svc>[\w-]+)\] .*? took (?<ms>\d+)ms/gm
  let m: RegExpExecArray | null, slow = 0, errors = 0
  while ((m = re.exec(log)) !== null) {
    if (Number(m.groups!.ms) > 400) slow++
    if (m.groups!.level === 'ERROR') errors++
  }
  const masked = log.replace(/user=(u\d+)/g, (_, u: string) => 'user=' + u.length)
  const fields = log.split(/\s+|=/).length
  let warns = 0
  for (const line of lines) if (/\bWARN\b/.test(line)) warns++
  const ids = log.match(/id=\d+/g)!.length
  total += slow + errors + masked.length + fields + warns + ids
}
console.log(total)
