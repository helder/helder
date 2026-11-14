# Contributing

## Docs

The docs are Markdown pages under `docs/`, published with the examples'
site (GitHub Pages, `.github/workflows/pages.yml`). They are the source of
truth: a package's README that has pages is generated from them.

- **Pages**: `docs/<section>/<page>.md`, in the order `docs/docs.json`
  lists them (the sidebar, previous and next). A page starts with its
  title, `# Title`; its sections are `##`. Markdown as GitHub renders it,
  less raw HTML: headings, paragraphs, lists, fenced code (` ```haxe `,
  ` ```ts ` highlighted), tables, quotes. Links: another page as
  `world.md#fog`, a file of the repository from its root as
  `/src/helder/asset/README.md` (both work on GitHub too).
- **Examples**: `<Example id="scene-nodes"/>` alone on a line plays an
  example in the page (a WebAssembly island, Play to start) with its
  source beside it: the file itself, so what a page shows is what builds.
  `id` is an example of `examples/` or `docs/examples/` as the examples'
  page names it (its directory); `file="Showcase.hx"` shows another file
  of its directory; `region="a,b"` shows only the lines between
  `// #region a` and `// #endregion` (and b's).
- **New examples** for a page go in `docs/examples/<id>/`: a small program
  with the examples' header (`// title:`, `// summary:`, `// tags:`,
  `// demo: canvas WxH`), one feature each. A `main.ts` beside the Haxe
  program, with a header too, is its TypeScript twin: shown in a tab
  beside it. They are not listed on the examples' page; the examples lane
  builds them (`bun run test examples`).
- **READMEs**: `docs/docs.json`'s `readmes` name the READMEs each
  section's pages make (`src/helder/scene/README.md`, ...). After editing
  a page, run `node site/docs/readme.mjs`; do not edit those READMEs by
  hand. The examples lane fails when one is not what the pages make
  (`node site/docs/readme.mjs --check`).
- **Building**: `node site/build.mjs` (`bun run site`) builds the examples
  for the web, the index and the docs into `bin/site`
  (`SITE_SKIP_DATA=1`: without the examples that fetch tens of MB of
  models). Serve `bin/site` (any static server) and open `docs/`.
  `bun run site:check` (Playwright) opens every page, its sources and tabs,
  and plays the docs' own examples. An unknown example, region, component
  or page link fails the build.

The pages are rendered by `site/docs/Docs.hx`: helder.web's static
renderer, helder.syntax's lexer for the highlighting (Markdown.hx is the
parser), built natively and run by `site/build.mjs`.
