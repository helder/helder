# The TypeScript fuzzer

A differential fuzzer of helder's TypeScript: random programs that
type-check under helder's config by construction, run by node (types
stripped: the reference) and by helder's compiler natively and, one
program in five, as wasm32-wasi. A difference in what they print, a
crash, a hang (30 s), or a program tsgo accepts that helder refuses is a
finding, shrunk to a small program.

```sh
node tests/typescript/fuzz/fuzz.mjs --seconds 600        # ten minutes, seed 0
HELDER_PROPERTY_SEED=random node tests/typescript/fuzz/fuzz.mjs --programs 50
node tests/typescript/fuzz/fuzz.mjs --seed 7 --program 12   # that program alone
node tests/typescript/fuzz/fuzz.mjs --lies --seconds 300  # a type lie in each case
```

| | |
| --- | --- |
| `--seconds n`, `--programs n` | a time budget, or a number of programs (20) |
| `--seed n` | HELDER_PROPERTY_SEED's, else 0 (`random`: a new one, printed) |
| `--program i` | program i of the seed alone |
| `--cases n` | cases a program (40) |
| `--jobs n` | compilation servers, one program each at a time (2) |
| `--wasm k` | one program in k also as wasm32-wasi (5; 0: none) |
| `--lies` | one deliberate type lie per case (below) |
| `--out dir` | its programs, binaries and findings (bin/typescript-fuzz) |
| `--store dir` | the findings kept for the next run (`<out>/properties`) |
| `--no-shrink`, `--write` | findings as they are; shrunk ones into tests/typescript/cases (or diverge/) |
| `--known` | also what helder is known to get wrong (below) |

**Programs** (`Generator.mjs`, `Program.mjs`): a program is 40 independent
cases, each a function printing a labelled trace through an exact printer
(`show`: `-0`, NaN and holes told apart, numbers by `String`, strings as
JSON, objects with their class and own keys), so one build covers 40 and
a difference names its case. The generator knows the type of every
binding in scope and draws only what the types describe: an element read
only in bounds (`i < a.length ? a[i] : x` with an integer i), a hole or a
widened array never read into a typed slot, no comparison TypeScript
calls unintentional. A case has a family (what it is mostly about) and a
few plain statements; the families follow what helder represents
specially (src/helder/typescript/README.md, "Strict"): numbers (-0, NaN,
2^31 and 2^53 edges, `%`, bit operations, `toFixed`), loop counters (the
Int64 rule and its near misses: a fractional start, a step of 2, written
in the body, captured, declared outside, `<=`, counting down), number
arrays (holes, a length past the end, freezing, widening to `unknown[]`,
in place, copies), classes with layouts and without (a computed name,
extending Map), their methods called directly and through the base,
accessors and statics, branded numbers, generics called with number (past
the 64 copies too), closures and `var`/`let` loop closures, strings built
in loops and their near misses, string methods, control flow (labels,
fallthrough, finally with return and break, exceptions across frames),
destructuring, spread and optional chains, generators and iterator
helpers, Map and Set (-0 and NaN keys), JSON and structuredClone, typed
arrays and DataView, RegExp, Date in UTC; an async case's microtasks,
promises and timers in node's order. eval, Function, Proxy, with,
`__proto__`, dynamic import, BigInt, Intl and WeakRef are never drawn,
nor what the specification leaves to the engine: an inconsistent sort
comparator (`cmp`, NaN last, is the generator's), transcendental Math,
`toString(radix)` of a fraction, `parseInt` past 20 digits in radix 36,
NaN's bits, timers of different delays (an async case's are all 0 ms,
counted: it ends once none is pending).

**Lies** (`--lies`): each case also holds one value its type does not
describe (`as`, JSON.parse into a typed slot, a missing argument, an
element past the end, `any` written into a number binding). Its trace
must be node's, or node's up to the lie and then helder's TSHX100 at the
lie's line (a missing argument's at the function's: it enters the
parameter there, as diverge/missing-argument.ts says).

**Driver** (`fuzz.mjs`, `Runner.mjs`, `Server.mjs`): each job keeps one
of helder's compilers up as a compilation server (`--server-connect`, the
protocol of src/helder/compiler/service/Resident.hx: tsgo and Haxe's side
warm between builds), while node runs the same file. Program i of a seed
is the same on every machine (`Random.mjs`, mulberry32 of the seed and
i). About 340 cases a minute on a Mac (M-series, 2 servers, a loaded
machine), 300 with findings being shrunk.

**Shrinking** (`Shrinker.mjs`): the failing case alone (or with the cases
before it it needs, halved away while it fails), then its tree edited:
statements dropped, blocks unwrapped, expressions made literals or one of
their own parts, each edit kept while the case fails the same way (the
same kind; a compiler's error the same message). A round's candidates are
one program's cases under their own ids, those tsc refuses left out
first, so a round is one build; a compiler's error at no line is shrunk
one candidate at a time. The result is checked again, then written as a
plain program (no harness, the values printed alone) when that still
fails, as `fuzz-<hash>.ts` in `<out>/found` (tests/typescript/cases with
`--write`, the way cases are compared: against node). Findings are kept
in the store and replayed first by the next run, removed once they pass,
as helder.test's properties are (src/helder/test/README.md).

**Lanes**: the typescript lane runs seed 0's 8 programs, unshrunk (about
a minute); the fuzz lane (`bun run test fuzz`) runs FUZZ_TS_SECONDS (300)
from FUZZ_SEED (random), its findings in bin/fuzz/properties.

**Known** (drawn only with `--known`): case mapping
(tests/typescript/cases/fuzz-d67c65fe.ts, skipped: SpecialCasing,
Final_Sigma, titlecase digraphs, the astral planes).
