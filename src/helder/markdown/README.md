# helder.markdown

Markdown parsed into a plain tree, and that tree shown as helder.ui's
nodes, in a plain look the app's look styles over.

```haxe
import helder.markdown.Markdown;
import helder.markdown.MarkdownView;

var doc = Markdown.parse(text);  // a Doc: blocks, frontMatter
var view = new MarkdownView({
	doc: doc,
	onLink: href -> if (StringTools.startsWith(href, "#")) view.scrollToHeading(href.substr(1)) else open(href),
	image: (src, alt) -> imageNodeFor(src)  // null: the alt text in its place
});
```

```ts
import { Markdown, MarkdownView } from "helder/markdown";

const view = new MarkdownView({ doc: Markdown.parse(text), onLink: href => open(href) });
```

## Parsing

`Markdown.parse(text)` reads CommonMark 0.31 (its block structure, line
by line against the open blocks as commonmark.js does: quotes, lists and
their items, tight and loose, fenced and indented code, setext and ATX
headings, rules, HTML blocks, reference definitions; tabs as columns of
4) and its inlines (delimiter runs by the spec's algorithm, code spans,
links and images inline, full, collapsed and shortcut, autolinks,
backslash escapes, HTML5's entities, hard and soft breaks), with GitHub's
extensions: tables (aligned columns), task list items (`[ ]`, `[x]`),
`~strikethrough~`, and extended autolinks (`www.`, `http://`, `https://`,
`ftp://` and addresses in text). Raw HTML is kept as text (`Html` blocks
and inlines), nothing is sanitized because nothing is rendered as HTML. A
front matter (`---` on the first line, up to the next `---` or `...`) is
taken off the top as a string (`doc.frontMatter`).

The tree is Haxe enums (`Doc.hx`): blocks `Heading(level, id, content)`
(`id`: GitHub's slug, unique in the document), `Paragraph`, `List(ordered,
start, tight, items)` (an item's `task`: true, false or null), `Quote`,
`Code(info, text)`, `Table(align, head, rows)`, `Rule`, `Html`; inlines
`Text`, `Emphasis`, `Strong`, `Strike`, `CodeSpan`, `Link(href, title,
content)` (href as written, escapes resolved, not percent-encoded),
`Image(src, alt, title)`, `Autolink(href, text)`, `SoftBreak`,
`HardBreak`, `Html`. `Markdown.plain(content)` is inlines' text,
`Markdown.slug(text)` a heading's id.

Containers and inlines nested past 100 levels are kept as text (as
markdown-it does), and a link's destination takes up to 32 nested
parentheses (the spec allows a limit), so every input parses in about
linear time: 10,000 `*`, `[`, `[a](`, `<!--` or nested `**` take
milliseconds (`Markdown.test.hx`).

Tests (`Markdown.test.hx`, natively, as wasm32-wasi and on Eval): 215 of
the CommonMark spec's 652 examples, about a third of each section's,
rendered to HTML as commonmark.js renders them, all passing; of the whole
spec 646 pass, the other six on purpose (front matter: 96 and 98; GFM's
autolinks in text: 606, 608, 611 and 612). cmark-gfm's examples of the
extensions (tables, task lists, strikethrough, autolinks) pass too.

## MarkdownView

`new MarkdownView(props)` is a node showing a `Doc`: each top-level block
in a row, in a scroller (`scroll: false`: as tall as its blocks, for a
preview; `blocks: n`: the first n alone). Past 300 blocks the scroller is
a `VirtualScroll` (helder.ui's README, Long lists): only the rows in view
are made, each measured once shown. `scrollToHeading(id)` brings a
heading to the top (a `#id` link), `headings()` lists their ids.

`update(doc)` shows another doc in the same view: a reply streamed in,
parsed whole again at each chunk (parsing is linear). The top-level
blocks equal to the last doc's, from the first, keep their rows (their
nodes, a selection in them, the scroll); the rows from the first that
differs are made again (as a reply grows, the last block, and the ones
appended). An open code fence shows what came so far and closes when
its ``` does. A long document's VirtualScroll is made again whole.

```haxe
var view = new MarkdownView({doc: Markdown.parse(""), scroll: false});
function chunk(text:String) {
	reply += text;
	view.update(Markdown.parse(reply));
}
```

- **Links** (`Link`, `Autolink`, a link around an image) call
  `onLink(href)`; the app decides what a relative path, an anchor or a
  URL opens. `linkPart(href)` gives a link's span a part of the app's
  look (its chips: a screen's, a file's; null: `markdown-link`).
- **Images** call `image(src, alt)` for a node (an `ImageNode`, its image
  set once it is decoded); without one the alt text stands in
  (`markdown-image-alt`). A paragraph with images is a wrapping row of its
  texts and images.
- **Code blocks** are a read-only `CodeView` (helder.ui.code): highlighted
  where `CodeLanguages` knows the fence's language (`ts`, `tsx`, `js`,
  `hx`/`haxe`, `helder`, `sql`), plain otherwise; `codeFont` and
  `codeSize` set its font.
- **Text** is one selection, as a browser's page: the view is a
  selectable scope (helder.ui's `Node.selectable`), so a drag runs from
  one block into the next (headings, paragraphs, list items, quotes,
  table cells, code blocks), a double click selects a word, a triple a
  line, Shift extends; Mod+C copies it (a blank line between blocks, a
  line between list items and table rows, a tab between cells, code as its
  text; markers and task boxes not in it), Mod+A selects the whole
  document once a press in it left the focus there. A long document's
  rows out of view keep their part, and are made for their text when
  copied. Spans are in their parts.

Every node's tag is its part, its style the plain look's with the
`Look`'s part of that name over it (`Look.with`'s `parts`; the look in
scope when the view is made):

| Part | What |
| --- | --- |
| `markdown`, `markdown-scroll`, `markdown-row` | the view, its scroller, a top-level block's row (the column's width, the space between blocks) |
| `markdown-h1` ... `markdown-h6`, `markdown-p` | headings, paragraphs |
| `markdown-quote` | a block quote (its bar: a left border) |
| `markdown-list` (`markdown-list-tight` over a tight one's), `markdown-item`, `markdown-marker`, `markdown-task` (`checked` when ticked), `markdown-task-mark`, `markdown-item-body` | lists |
| `markdown-code` | a code block's box, around its CodeView |
| `markdown-table-scroll`, `markdown-table`, `markdown-th`, `markdown-td` | tables (a grid, scrolled sideways when wide) |
| `markdown-rule`, `markdown-html`, `markdown-image` (over an image's own style), `markdown-image-alt` | the rest |
| `markdown-p-text`, `markdown-em`, `markdown-strong`, `markdown-del`, `markdown-code-span`, `markdown-link` | spans in text |

Space between nested blocks is their container's `row-gap` (a quote's, a
list's, an item body's). Emphasis, strong and strikethrough are italic,
bold and struck through whatever the look. Without parts of the look's,
the plain look is GitHub's proportions (`examples/markdown`).

```haxe
static final look = Look.base.with({
	parts: {
		"markdown-row": t -> {width: "100%", maxWidth: 760, padding: [0, 32, 14, 32]},
		"markdown-h1": t -> {fontSize: 28, fontWeight: 600, color: t.fg},
		"markdown-p": t -> {lineHeight: 1.6, color: t.fg},
		"markdown-link": t -> {color: t.accentInk},
		"markdown-code": t -> {padding: [10, 12, 10, 0], borderRadius: t.radius, background: t.fill},
		"markdown-quote": t -> {padding: [0, 0, 0, 12], borderWidth: [0, 0, 0, 3], borderColor: t.line, color: t.fg2}
	}
});
```

Tests: `MarkdownView.test.hx` (headless: the parts, a link's press,
images, a long document's rows and a heading scrolled to, a streamed
reply's blocks kept: chunks appended, a fence streamed then closed, a
list growing item by item), `index.test.ts`
(from TypeScript).
