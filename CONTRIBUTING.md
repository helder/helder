# Contributing

## Docs

The docs are a short guide under `docs/`, published with the examples'
pages on [helder.build](https://helder.build/docs/)
(helder.build's deploy builds them from main, daily and on its own pushes).
They show what helder can do; every function and detail lives in the
packages' READMEs (`src/helder/<package>/README.md`), which the pages link
to and do not repeat.

- **Pages**: `docs/index.md` (the introduction, `/docs/`), then
  `docs/<group>/<page>.md` (`/docs/<group>/<page>/`), in the order
  `docs/docs.json` lists them (the sidebar, previous and next); a page id
  with a slash (`3d/models`) is a sub-page, indented under its parent.
  Every page has the same shape, about one or two screens: a paragraph of
  what and why, one visual, one or two short samples, a "What else" list
  in plain words, and `<Reference to="ui,view"/>` (the READMEs). Markdown
  as GitHub renders it, less raw HTML. A ` ```ts ` fence followed by a
  ` ```haxe ` one is one sample with a TypeScript and Haxe switch (the
  reader's choice is remembered). Links: another page as `views.md`, a
  file of the repository as `/src/helder/asset/README.md`.
- **Visuals**: `<Example id="scene-nodes"/>` plays an example of
  `examples/` or `docs/examples/` live in the page (a WebAssembly island,
  started once in view); `region="a,b"` also shows those lines of its
  source. Where no example runs in a browser, `<Image src="x.webp"/>`
  shows a frame from `site/visuals/`, taken headless by
  `node site/visuals.mjs` (`bun run site:visuals`; add a program to its
  list, run it, commit the pictures). `<Terminal>` and `<Platforms/>`
  are the others.
- **New examples** for a page go in `docs/examples/<id>/`: a small program
  with the examples' header (`// title:`, `// summary:`, `// tags:`,
  `// demo: canvas WxH`). A `main.ts` beside the Haxe program, with a
  header too, is its TypeScript twin. They are not listed on the examples'
  page; the examples lane builds them (`bun run test examples`).
- **Moved pages**: `docs/docs.json`'s `moved` sends an old address on to
  its page, so links from elsewhere keep working.
- **Building**: `node site/build.mjs` (`bun run site`) builds the examples
  for the web, their pages and the docs into `bin/site`
  (`SITE_SKIP_DATA=1`: without the examples that fetch tens of MB of
  models). Serve `bin/site` (any static server) and open it.
  `bun run site:check` (Playwright) opens every page, plays every live
  visual, switches the samples' languages and checks phone widths; CI's
  site job (`.github/workflows/ci.yml`) runs both on every pull request.
  An unknown example, region, picture, component, page or heading link
  fails the build.

The pages are rendered by `site/docs/Docs.hx`: helder.web's static renderer, helder.syntax's lexer
for the highlighting (Markdown.hx is the parser), built natively and run
by `site/build.mjs`. One sheet,
`site/site.css`, styles them and the examples' pages, in helder.build's
look; the host's theme (`SITE_THEME`, `site/build.mjs`) sets the top bar's
links, a notice, the footer and its own sheets over it.

## Tests

`bun run test` runs the lanes that need no GPU, display or browser;
`bun run test <lane>` runs one (`bun run test help` lists them,
[tests/README.md](tests/README.md) says what each checks).

- **Unit tests** are `*.test.hx` (helder.test) next to their source:
  `src/helder/jobs/Jobs.test.hx` for `src/helder/jobs`. `helder test`
  finds them; the test lane runs them all.
- **A new module with a model or an inverse ships a property test**
  (helder.test's `property`, or `stateful` for a sequence of operations):
  a parser against its printer, an edit against its undo, a structure
  against a plain array. Reviews ask for it.
- **Checks** are native or integration programs that exit non-zero on a
  failure: `*Check.hx` in `tests/<package>/`, run by a lane of
  `tests/lanes/`.
- **Fixtures** are data the tests read, in `tests/<package>/fixtures`
  (`*Fixture.hx` when the data is Haxe).
- **Benches** measure and do not fail: `tests/bench/*Bench.hx`, each run
  by `bun run test bench <name>`.
- **Goldens** are PNGs beside their check, written by `BLESS=1`. Keep them
  small: the least size that still shows what the check proves.
