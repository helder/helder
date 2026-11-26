// A seeded generator (mulberry32 over a seed and a program's index mixed
// by murmur's finalizer): a program is the same from the same pair on
// every machine.
export class Random {
  #state

  constructor(...seeds) {
    let h = 0x9e3779b9
    for (const s of seeds) h = mix(h ^ mix(s >>> 0))
    this.#state = h >>> 0
  }

  next() {
    let t = this.#state = (this.#state + 0x6d2b79f5) >>> 0
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }

  int(n) {
    return Math.floor(this.next() * n)
  }

  range(lo, hi) {
    return lo + this.int(hi - lo + 1)
  }

  chance(p) {
    return this.next() < p
  }

  pick(items) {
    return items[this.int(items.length)]
  }

  // [[weight, value], ...]: a value by its weight
  weighted(pairs) {
    let total = 0
    for (const [w] of pairs) total += w
    let x = this.next() * total
    for (const [w, v] of pairs) if ((x -= w) < 0) return v
    return pairs[pairs.length - 1][1]
  }
}

function mix(h) {
  h = Math.imul(h ^ (h >>> 16), 0x85ebca6b)
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35)
  return (h ^ (h >>> 16)) >>> 0
}

// a seed from text (HELDER_PROPERTY_SEED: a number, or random)
export function seedOf(text) {
  if (text == null || text === '') return 0
  if (text === 'random') return Math.floor(Math.random() * 2 ** 31)
  const n = Number(text)
  if (!Number.isSafeInteger(n)) throw new Error(`a seed is a number: ${text}`)
  return n >>> 0
}
