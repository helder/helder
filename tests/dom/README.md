# DOM conformance

helder.dom's parser against html5lib-tests' tokenizer tests and the tree
construction tests web-platform-tests keeps (they moved there from
html5lib-tests), natively, then against parse5:

```sh
bun run test dom            # BLESS=1: manifest.json from the results
```

- `fixtures/tokenizer/*.test`: html5lib-tests' tokenizer tests (JSON), a
  case each initial state; the tokens and the parse errors (code, line,
  column) must be the test's. Left out: `xmlViolation.test` (html5lib's
  coercion to an XML infoset).
- `fixtures/tree-construction/*.dat`: WPT's
  `html/syntax/parsing/resources`: documents and fragments (`#document-fragment`,
  an SVG or MathML context as `svg path`), their trees in html5lib's format
  (`Dump.hx`). A `#script-on` case is skipped: the parser's scripting is off.
- `manifest.json`: every case listed (`schema`, the two revisions, then
  the cases in order). A case without a status must pass; `pending` (its
  reason) must fail, and passing fails the run until BLESS=1 requires it;
  `skip` (its reason) is not run. None is pending.
- `DomConformanceCheck.hx`: the runner (natively; a filter as its argument
  runs the cases whose id contains it).
- `parse5.mjs`, `DomDump.hx`, `parse5-known.json`: the differential check,
  5,000 generated documents (seeded) and the repository's pages (and the
  bench's, when bin/bench/html has them) parsed by helder (DomDump) and by
  parse5 (the pinned devDependency), the same tree but for the documents
  listed in parse5-known.json, each a difference of parse5's from today's
  standard checked by hand (CDATA in integration points, `<search>`, forms
  in a template's table, a template bounding the table scope, frameset-ok
  after a template); parse5 8.1.1 predates `<select>`'s content and
  processing instructions, so inputs with `<select` or `<?` are left out.
- `entities.mjs`: src/helder/dom/Entities.hx made from the HTML Standard's
  entities.json, its bytes pinned by their hash.

`import-html5lib.mjs` makes the fixtures again at the revisions it pins
(fetched into bin/dom/upstream, or from checkouts given), keeping the
manifest's statuses; new cases come in pending:

```sh
node tests/dom/import-html5lib.mjs [html5lib-tests] [wpt]
BLESS=1 bun run test dom
```

html5lib-tests' serializer tests are not imported: they serialize token
streams the way html5lib's serializer does (unclosed elements, single
quotes, unquoted values), not by the HTML Standard's algorithm, which the
unit tests and the round-trip property check (src/helder/dom/Dom.test.hx).

The fixtures are html5lib-tests' (MIT, `HTML5LIB-LICENSE`) and WPT's
(BSD-3-Clause, `WPT-LICENSE`).
