# helder.test

Tests as bun and jest write them, without macros: tests registered by
calls, assertions as plain functions located by their caller's position
(`haxe.PosInfos`), async tests as coroutines on `helder.async`'s loop.
Files are `*.test.hx`, built and run by `helder test` (src/helder/cli).

```haxe
// src/geom/Vec.test.hx
package geom;

import helder.async.Async;
import helder.test.Test;

function tests() {
  describe("Vec", () -> {
    var v = new Vec(0, 0);
    beforeEach(() -> v = new Vec(3, 4));
    test("length", () -> approx(v.length(), 5));
    test("fields", () -> equals({x: v.x, y: v.y}, {x: 3.0, y: 4.0}));
    test("parse", () -> {
      var p = require(Vec.parse("1,2"));     // stops the test on null
      equals(p.x, 1.0);
    });
    test("later", () -> fail("todo")).skip();
  });
  test("loads", async(() -> {
    Async.delay(0.01);
    assert(true);
  })).timeout(1);
}
```

```sh
bun run helder test                       # every test file, natively
bun run helder test geom -t length        # the files under geom, tests named so
bun run helder test --target all --watch  # natively and as wasm32-wasi
bun run helder test --target interp       # the files that opt in, on Eval
```

helder ships natively and as wasm32-wasi, so those are the targets
(`all`); Eval matters only for code that runs at compile time (macros:
the shader compiler, ui's StyleFieldsMacro and AttrMacro). A test file
opts in to `interp` with `@:test.interp` on its `tests()` (the CLI reads
it in the file; no macro):

```haxe
@:test.interp
function tests() { ... }
```

The others are never built for Eval, so they need no `#if` for it (they
may use hxmc.unsafe, helder.os's windows); `--target interp` with no file
opting in says so in a line and passes. Opted in: AssetPath.test.hx
(AssetMacro checks an asset's path with it at compile time). No lane runs
`interp`: the opt-in is for running such a file by hand.

## Files

A test file is a module with a module-level `tests()` function, named
`*.test.hx`, under `src/`, `tests/` or one of the project's class paths
(package.json's `"haxe": {"classPath"}`), never under `bin/` or
`node_modules/`. Its `package` line is its directory's under that root.
It can use what its package can (`@:allow` included); private helpers are
`private function`s.

Haxe takes no dot in a module's name ("Module "Vec.test" does not have a
valid name"), so `helder test` links each one into bin/test/src under its
package's directories as `Vec_test.hx` (a symbolic link, else a hard link,
else a copy, each kept the file's content), generates
bin/test/src/HelderTestMain.hx, whose main calls each `tests()` and then
the runner, builds that once with the project's class paths plus
bin/test/src, and runs it. Positions are the same in the link, so the
compiler's output and the program's are written with the real paths
again (the CLI rewrites them, and the runner maps the paths PosInfos
records itself, for a program run directly).

Editors: the Haxe display server takes `Vec.test.hx` for the module
`geom.Vec` (the name up to the first dot): with a `Vec.hx` beside it,
requests answer for that file (no diagnostics, no hover, no completion in
the test), without one they fail ("Type not found : geom.Vec"). The link
does not help (it is resolved to the real path); a copy would. Until the
editor extension (phase 6), a test file is written without the language
server. Windows makes symbolic links only in developer mode, and hard
links on the same volume: else the copy, rewritten when the test file
changes.

## Registering

`import helder.test.Test;` gives the functions:

- `test(name, body)`, `describe(name, body)` (its body registers its tests,
  hooks and groups at once); both return the entry, for `.skip()`,
  `.only()` (only those marked, across files, run; a group's mark covers
  its tests) and `.timeout(seconds)` (a group's: its tests').
- `beforeEach`, `afterEach` (inner first, also after a failure),
  `beforeAll`, `afterAll`, in a file or a group. A failed beforeAll is
  reported and leaves its group's tests out.
- A body is a plain function, or `async(coroutine)`: a test or hook that
  suspends, run on `helder.async`'s loop with a timeout (5 s, else
  `.timeout()` or `--timeout`). helder.async is linked only into programs
  with an `async`. In the browser's loop (wasm32-wasi) the run goes on as
  each async step ends: nothing blocks.

(`async(...)` and not an overload of `test`: overload resolution types
the argument once without the coroutine's expected type, and a coroutine
lambda nested in the body (`Async.scope(task -> ...)`) fails to type.)

## Assertions

| | |
| --- | --- |
| `assert(cond, ?msg)` | a failure if false |
| `equals(actual, expected, ?msg)` | deep (`Equal.diff`): numbers by value, arrays, lists, maps, anonymous structures and instances by field, enums, Bytes, Dates; both values shown, and where they differ (`.list[0].a`) |
| `notEquals(actual, expected)` | |
| `approx(actual, expected, epsilon = 1e-6)` | |
| `throws(fn):Dynamic` | the error as thrown (an exception, or a value); a failure if none. `throwsAsync(coroutine)` in a coroutine |
| `require(v, ?msg):T` | v, not null; null stops the test |
| `fail(msg)` | a failure, the test stopped |
| `snapshot(name, value)` | value (a String, or shown as a literal) against Vec.test.snap beside the file: written when missing, `-u` rewrites a changed one |

A failure is the file and line of the call, then its message; the test
goes on, except after `require`, `fail` or an error thrown (its message
and the frames above the runner's).

## Properties

A property is a test's assertions over generated values: `property(gen,
body)` runs body on 100 values of gen, and the first that fails is shrunk
to the smallest that still fails and reported with how to replay it.
Generators are `import helder.test.Gen;`'s.

```haxe
import helder.test.Gen;
import helder.test.Test;

function tests() {
  test("sort keeps the items", () -> property(array(int(-50, 50)), xs -> {
    var s = xs.copy();
    s.sort(Reflect.compare);
    equals(s.length, xs.length);
  }));
  test("parse never throws", () -> property(string(char(true)), s -> Markdown.parse(s), {cases: 300}));
}
```

| | |
| --- | --- |
| `int(min, max)`, `float(min, max)`, `bool()` | shrinking to 0, or the bound nearest to it; floats to round numbers |
| `pick(values)`, `oneOf(gens)`, `constant(v)` | shrinking to the first |
| `array(item, min = 0, max = 100)` | mostly short, sometimes up to max; shrinking to fewer items |
| `string(?chars, min = 0, max = 2000)`, `char(nul = false)` | char(): ASCII mostly, and whitespace and line ends, right-to-left letters and marks, combining marks, emoji sequences, other scripts; NUL and controls with nul |
| `recursive(base, extend, depth = 3)` | base, or extend's of a smaller one |
| `mutated(seeds, most = 8)` | Bytes: one of seeds (a map of names to real files' bytes) with 1 to most mutations (bits flipped, edge values, huge header ints, numbers made nines, runs cut, repeated, cut out, zeroed, spliced from another seed), each noted as the case's value; shrinking to fewer, earlier ones of the first seed |
| `g.map(f)`, `g.filter(ok)` | filter draws three times, else rejects the case |
| `c -> ...` | a Gen of your own is a function of the case's Choices: `c -> {x: c.draw(int(0, 9)), y: c.draw(int(0, 9))}`; `c.choice(bound)`, `c.weighted(p)`, `c.note(text)` |
| `assume(cond)` | the case rejected, not failed; over 4 rejected for each case asked, or none run, fails the property ("the generator rejects too much") |

How it works (Hypothesis' design): a case is the sequence of choices
its generators made (Choices), each an int in 0 to a bound, 0 its
simplest. A failure is shrunk by editing that sequence and running the
body again (spans of a draw deleted, an array's item or a stateful step
with them; chunks deleted and zeroed; each value lowered, a value moved
onto a later one; same-length siblings sorted), keeping the edit while the
case still fails, until nothing changes or the budget is spent. A
sequence that runs out while replayed is overran: not a failure. Each
case's failures are its assertions' (or what it threw), kept apart from
the test's until the smallest is reported:

```
src/geom/Vec.test.hx:12: property failed after 4 cases, shrunk 9 times:
  [101]
  src/geom/Vec.test.hx:13: over 100
  replay: {replay: "1 101 0"}, or {seed: 0} (HELDER_PROPERTY_SEED=0)
```

Options (the last argument): `cases` (100), `seconds` (5: generating, and
again shrinking), `seed`, `replay` (a reported sequence: that case alone),
`steps` (stateful: 50), `limit` and `memory` (robustness, below). The seed is 0 unless HELDER_PROPERTY_SEED (a
number, or `random`) or `seed` says, mixed with the property's test and
place in it, so a run's cases are the same on every run and target (host,
wasm and interp draw the same: Property.test.hx's snapshot). A failure's
sequence is kept in bin/test/properties (one file a property, named by its
file, test and index in it) and replayed first on the next run, shrunk
further if it still fails, removed once it passes. Bodies are plain
functions (no `async` inside a property).

A robustness property (`limit`: a case's most seconds) is watched
natively by a thread of its own, since a case that hangs, crashes or eats
the machine cannot report itself: each case is kept in the store before
it runs, past `limit` the watchdog prints the case (its notes, its
replay) and ends the process (exit code 3), as it does when a case grows
the process by more than `memory` MB (macOS' and iOS' footprint, Linux's
and Android's resident set; unchecked on Windows): against the case's own
start, a full collection first when the footprint has drifted half the
budget since the last, the peak while it runs (the watchdog's readings)
and what it keeps after a full collection once it ends. A native crash
leaves the case there too. The next run replays the kept case first,
saying so. Such a case is not shrunk (the process ended): its replay is
the regression test to write. HELDER_PROPERTY_SOAK (seconds) runs each
robustness property that long, its cases unbounded (the fuzz lane: `bun
run test fuzz`); eval and wasm32-wasi run them without the watchdog.

```haxe
test("a mutated image: decoded, or an ImageError", () -> property(mutated(seeds), b -> {
  try Image.decode(b) catch (e:ImageError) {}
}, {cases: 150, seconds: 3, limit: 10, memory: 256}));
```

A stateful property draws steps and runs them on a system made for each
case, its check holding after setup and after each step; a step's draws
are its arguments, shown with it; shrinking takes steps out:

```haxe
test("a stack against an array", () -> stateful({
  setup: () -> {real: new Stack(), model: []},
  steps: [
    {name: "push", run: (s, c) -> {
      var v = c.draw(int(0, 9));
      s.real.push(v);
      s.model.push(v);
    }},
    {name: "pop", run: (s, c) -> equals(s.real.pop(), s.model.pop()), when: s -> s.model.length > 0}
  ],
  check: s -> equals(s.real.length, s.model.length),
  teardown: s -> {}
}));
```

reported as its steps: `push(0)` `push(0)` `push(0)` `push(0)`, then the
failure. A headless Ui is a system too: src/helder/ui/GridScroll.test.hx
wheels, resizes, presses and keys a VirtualGrid, its scroll, selection and
focus checked after each. Tests: Property.test.hx (shrinking's classic
cases, replays, the store, rejections, stateful),
src/helder/markdown/Markdown.test.hx's properties, the robustness ones
(tests/image, tests/pdf, tests/media and tests/text's Fuzz.test.hx).

## Running

The runner (`Runner`) prints each file, then `(pass)`, `(fail)` with its
failures, or `(skip)` per test with its time, and a summary (pass, skip,
fail, checks, the time); exit code 1 on a failure. `helder test`:

| | |
| --- | --- |
| `[filter...]` | a filter that is part of a test file's path picks those files; any other one the tests whose full name ("describe > test") contains it |
| `-t <text>` | the tests whose full name contains it; `/text/` a regex (the generated main gives the runner EReg only then) |
| `--target <t>` | `host` (natively, the default; on Linux in the dynamic glibc mode, as `helder build`'s, so that tests of helder.os link the system's libraries), `wasm` (wasm32-wasi under node: src/helder/test/wasi.mjs, node's WASI with the working directory and helder.async's imports), `all` (`host` and `wasm`), `interp` (Eval, only the files with `@:test.interp`; asked for, never in `all`), or several (`host,interp`); a line per target at the end |
| `--watch`, `-w` | built and run again after each change under the roots (mtimes to the nanosecond: a save within the same second is seen); builds go to a compilation server (`haxe --wait`), stopped with the CLI on ctrl-c or SIGTERM |
| `-u` | snapshots rewritten |
| `--timeout <s>` | an async step's limit |

Sizes and times (this repository's 42 tests, 3 files, Linux x86-64):
a file with one plain test builds to 262 KB natively and 137 KB for
wasm32-wasi (a hello world is 122 KB and 55 KB; 297 KB natively before
hxmc trimmed its std overrides by DCE, #89), 0.58 s from nothing and 0.21 s
from the module cache, and runs in 2 ms. The repository's build: 0.55 s
cold, 0.21 s cached (0.26 s for wasm), 0.25 to 0.45 s through the
compilation server; Eval compiles and runs it in 0.42 s (0.06 s with
no test run).

## TypeScript

`*.test.ts` and `*.test.tsx` files are found where `*.test.hx` are (and
under a directory named: `helder test examples/ts-todo`), built by helder's
compiler into a program of their own and run natively and as wasm32-wasi,
through the same runner: its groups, hooks, `-t`, `.only()`, `.skip()`,
`.timeout()`, snapshots and report. They import `helder/test`
(src/helder/test/index.ts, over its own `runner.d.ts`: helder.test.Script)
and register at their top level:

```ts
// examples/ts-todo/todos.test.ts
import {describe, test, beforeEach, equals} from 'helder/test'
import {added, left} from './todos'

describe('todos', () => {
  let list = []
  beforeEach(() => {list = added([], 1, 'Buy milk')})
  test('left', () => equals(left(list), '1 item left'))
  test('later', async () => {
    await new Promise(r => setTimeout(r, 1))
    equals(list.length, 1)
  }).timeout(1)
})
```

Properties are the same (`property`, `stateful`, `assume`, and `gen`,
`int`, `float`, `bool`, `pick`, `oneOf`, `constant`, `array`, `string`,
`char`, `recursive`, a Gen's `map` and `filter`; values shown as `show`
writes them): src/helder/test/property.test.ts. A Gen of your own is
`gen(c => ({x: c.draw(int(0, 9))}))`.

The assertions are Haxe's (`assert`, `equals`, `notEquals`, `approx`,
`throws`, `rejects` for a promise, `require`, `fail`, `snapshot`), each
failure at its call's file and line: helder's compiler gives each call of
one its position, as Haxe's PosInfos (their last parameter, `at`,
`lower/Definitions.hx`). `equals` compares JavaScript's values (`diff`:
primitives by SameValueZero, arrays, plain objects and instances of one
prototype by their own properties, Map, Set, Date, typed arrays) and shows
them as `show` writes them (`{a: [1, 2]}`, `Point {x: 3}`, `Map {"k" =>
1}`). A body may be async: its promise is awaited within its timeout.
`Foo.test.ts`'s snapshots are `Foo.test.snap`, as `.test.hx`'s.

TSX mounts headless with helder/story's `tree(story({...}), width,
height)` (a Ui of that size, helder.text's own shaping: the same tree on
every OS), which a snapshot keeps (examples/ts-todo/app.test.tsx: its
view, typed into and filtered).

`helder test`'s main for them is bin/test/ts/main.ts: for each file a
module telling the runner its name, then the file, imported (ES modules run
in the order imported). TypeScript does not run on Eval, and the tests do
not run on node (helder/test is helder.test's runner, Haxe); `--target
interp` leaves them out.

## Not yet

A macro (`assert(a == b)` showing both sides, tests collected without
`tests()`), golden images beside snapshots, the runner's sub-runs in
process (helder.test's own tests run the program again for what fails),
`test.each`, coverage, the browser as a target, the CLI as a binary on
npm. Tests: `*.test.hx` here (`bun run helder test src/helder/test`), and
the `test` lane (`bun run test test`).
