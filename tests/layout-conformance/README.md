# Layout conformance

helder.ui's flexbox and grid against the boxes Chrome measured for
[Taffy](https://github.com/DioxusLabs/taffy)'s test fixtures, in pure Haxe
on Eval:

```sh
bun run test layout-conformance            # BLESS=1: manifest.json from the results
```

- `fixtures/<category>/<name>.json`: one of Taffy's tests (`flex`, `grid`,
  `gridflex`, `leaf`): a style tree in CSS's own names and values, and the
  boxes of its four variants (border-box or content-box, ltr or rtl), one
  `[x, y, width, height]` a node in pre-order, x and y from the parent.
  Each records its upstream path and Taffy's revision
  (`schema/fixture.schema.json`).
- `manifest.json`: the ordered coverage gate (`schema/manifest.schema.json`).
  Every fixture is listed, decoded and validated; each of `variants` is laid
  out and required to pass unless `pending` gives its reason (`unmapped:`
  a property or value outside the subset; `differs:` the first box that
  does). A pending case that passes fails the run too, until BLESS=1
  requires it. `skip`: validated, not laid out (and why).
- `capabilities.json`: the subset of CSS layout helder.ui claims against
  that reference, what it leaves out and where its defaults differ.
- `LayoutConformance.hx`: the runner. It maps the fixtures' CSS onto
  `Style` (CSS's initial values where helder.ui's differ), places the root
  in a max-content viewport as Taffy does, and compares within half a
  pixel. Text is Taffy's test measure, not a font: Ahem's 10px squares,
  lines broken only at U+200B (`HH​HH`), the first baseline 8px down.

`import-taffy.mjs` makes the fixtures again from a Taffy checkout (its
`tests/xml`, which Taffy's gentest generates in Chrome from
`test_fixtures/*.html`), keeping the manifest's statuses; new cases come in
pending:

```sh
node tests/layout-conformance/import-taffy.mjs ../taffy
BLESS=1 bun run test layout-conformance
```

The fixtures are Taffy's, MIT licensed (`TAFFY-LICENSE`).
