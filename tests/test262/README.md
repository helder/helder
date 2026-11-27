# test262

tc39's conformance suite through helder's frontend as plain JavaScript:
`bun run test test262 [part of a path...]` (natively; `node
tests/test262/run.mjs` the same). The suite is a pinned checkout made in
bin/test262/checkout (run.mjs's REVISION, a sparse clone: the harness and
the directories in scope), never vendored.

Each directory's tests run in batches of 120, one program each: the harness
once (assert.js, sta.js and what the batch's tests include), each test a
function of its own called with the global `this`, the built-ins reachable
from the global object put back as they were after each test
(propertyHelper's verifyProperty deletes what it checks), a line per test.
An async test (`flags: [async]`) runs alone in its turn, its `$DONE` within
5 s; a runtime negative test passes when it throws its error's type. node
runs each batch first: a test that fails there fails the wrapping, not
helder, and is set aside. A batch helder does not build is built test by
test; a crash or a hang ends the test that started last, and the rest of
the batch runs again.

Out of scope, never run: flags noStrict, raw and CanBlock (a program is a
module: strict); module code and parse or resolution negatives (not yet);
features helder or a single realm leave out (BigInt, Intl, Temporal,
SharedArrayBuffer and Atomics, ShadowRealm, WeakRef and
FinalizationRegistry, cross-realm, explicit resource management, resizable
ArrayBuffers, Proxy, `__proto__`, setPrototypeOf, dynamic import, tail
calls, IsHTMLDDA, and stage 3 proposals); `$262`'s host hooks; eval and
Function; harness files that need them (fnGlobalObject.js is replaced by
`globalThis`).

**The gate** is manifest.json: every test that runs passes unless it is
pending there (with its failure); a failure not listed, or a pending test
that passes, fails the run, until `BLESS=1` writes the manifest from the
results (with a path filter: those tests alone). bin/test262/report.md has
the counts and the failure clusters.

First slice: built-ins Array, String, Object, JSON, Map, Set, Promise, Math
and Number. Not yet: the other built-ins, language/, module code, negative
parse tests.

<!-- counts -->
| area | pass | judged | rate | set aside (wrapping) | out of scope |
| --- | --- | --- | --- | --- | --- |
| built-ins/Array | 2124 | 2596 | 81.8% | 15 | 472 |
| built-ins/JSON | 105 | 116 | 90.5% | 0 | 50 |
| built-ins/Map | 119 | 136 | 87.5% | 10 | 58 |
| built-ins/Math | 276 | 317 | 87.1% | 0 | 10 |
| built-ins/Number | 310 | 331 | 93.7% | 0 | 9 |
| built-ins/Object | 2516 | 3091 | 81.4% | 52 | 268 |
| built-ins/Promise | 322 | 582 | 55.3% | 80 | 70 |
| built-ins/Set | 326 | 349 | 93.4% | 0 | 34 |
| built-ins/String | 1001 | 1076 | 93.0% | 46 | 101 |
| all | 7099 | 8594 | 82.6% | | |
<!-- /counts -->
