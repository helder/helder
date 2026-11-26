# helder.dom

The DOM as the WHATWG's DOM Standard defines it, and the HTML Standard's
parser and serializer: markup in, a tree of nodes out (and back), as a
browser builds it with scripting off. What helder's HTML and CSS to PDF
engine lays out.

```haxe
import helder.dom.*;

var doc = Dom.parse("<!doctype html><title>Report</title><p class=lead>Hi <b>there");
doc.title;                                    // "Report"
doc.mode;                                     // NoQuirks (Quirks, LimitedQuirks: the doctype's)
var p = doc.body.firstElementChild;
p.classList.contains("lead");                 // true
p.append(" and ", doc.createElement("i"));
Dom.serialize(doc);                           // the document as markup
var cells = Dom.parseFragment("<td>a<td>b", doc.createElement("tr"));
```

## Parsing

`Dom.parse(html)` is the HTML Standard's parser as it stands today
(html.spec.whatwg.org, November 2026): the tokenizer's states, character
references by the standard's table (`Entities.hx`, made from its
entities.json by tests/dom/entities.mjs, which helder.markdown reads too),
and tree construction's insertion modes: implied tags, the adoption agency
algorithm, foster parenting, the list of active formatting elements,
templates and their insertion modes, SVG and MathML with their tag and
attribute names' case and namespaces, the quirks modes from the doctype,
`<select>`'s content and `<selectedcontent>` (the current standard's, not
the older "in select" modes), processing instructions (`<?target data?>`:
ProcessingInstruction nodes, their pseudo-attributes), and a `<template
for=name>` patching the range between its `<?start name="..."?>` and
`<?end?>` markers. Scripting is off: no script runs and `<noscript>`'s
children are parsed as markup. Nothing is sanitized and no shadow root is
attached (a declarative one stays a template).

`Dom.parseFragment(html, context)` is the fragment parsing algorithm (what
`innerHTML` sets): the markup parsed as `context`'s children would be,
into a DocumentFragment of context's document.

Neither throws, whatever the input: bad markup recovers as the standard
says. `Dom.parse(html, errors)` also collects the parse errors (`{code,
offset}`): the tokenizer's with the standard's codes, the tree builder's
with codes of its own. Each node made by the parser has its source span,
`start` and `end` (offsets into the string; `-1` for a node made by
code): an element's from its `<` to after its end tag, or to where the
token that closed it began.

The input is a Haxe String: UTF-16 natively and as wasm32-wasi (offsets in
code units, a character outside the BMP two), code points on Eval. CR and
CRLF read as LF where they are met, so the offsets are the source's own.

## The DOM

The interfaces and their hierarchy are the standard's, with its names:

| | |
| --- | --- |
| `Node` | `nodeType`, `nodeName`, `parentNode`, `firstChild`, `lastChild`, `previousSibling`, `nextSibling`, `childNodes`, `ownerDocument`, `textContent`, `nodeValue`, `insertBefore`, `appendChild`, `replaceChild`, `removeChild`, `cloneNode`, `isEqualNode`, `compareDocumentPosition`, `contains`, `normalize`, `getRootNode`, `lookupPrefix`, `lookupNamespaceURI`, `isDefaultNamespace` |
| `Document` | `documentElement`, `doctype`, `head`, `body`, `title`, `mode` and `compatMode`, `contentType`, `createElement(NS)`, `createTextNode`, `createComment`, `createCDATASection`, `createProcessingInstruction`, `createDocumentFragment`, `createAttribute(NS)`, `importNode`, `adoptNode`, `getElementById`, `getElementsByTagName(NS)`, `getElementsByClassName` |
| `Element` | `namespaceURI`, `prefix`, `localName`, `tagName`, `id`, `className`, `classList`, `slot`, `attributes`, `getAttribute(NS)`, `setAttribute(NS)`, `removeAttribute(NS)`, `toggleAttribute`, `hasAttribute(NS)`, `getAttributeNames`, `getAttributeNode(NS)`, `setAttributeNode(NS)`, `removeAttributeNode`, `insertAdjacentElement`, `insertAdjacentText`, `innerHTML`, `outerHTML` |
| `CharacterData` | `data`, `length`, `substringData`, `appendData`, `insertData`, `deleteData`, `replaceData`; `Text` (`splitText`, `wholeText`), `CDATASection`, `Comment`, `ProcessingInstruction` (`target`, its attributes) |
| `Attr`, `DocumentType`, `DocumentFragment` | |
| `NodeList`, `HTMLCollection`, `NamedNodeMap`, `DOMTokenList` | live views: a node's children, its descendants a filter keeps, its attributes, an attribute's tokens |
| `DOMException` | `name` as the standard names the error: `HierarchyRequestError`, `NotFoundError`, `InvalidCharacterError`, `NamespaceError`, `InUseAttributeError`, `IndexSizeError`, `NotSupportedError`, `SyntaxError`, ... |

ParentNode's members (`children`, `firstElementChild`, `lastElementChild`,
`childElementCount`, `prepend`, `append`, `replaceChildren`,
`moveBefore`) are on Document, DocumentFragment and Element; ChildNode's
(`before`, `after`, `replaceWith`, `remove`) on Element, CharacterData and
DocumentType; NonDocumentTypeChildNode's (`previousElementSibling`,
`nextElementSibling`) on Element and CharacterData. Their arguments are
nodes or strings (`p.append("text", node)`). `new Document()` is the
standard's constructor's: an XML document; `Dom.parse`'s are HTML ones.

The algorithms are the standard's, with their errors: pre-insert's
validity checks (a second document element, a doctype after it, text in a
document, a node into its own descendant or its template's contents),
insert and remove, replace and replace all, adopt (into another document:
the node, its descendants, their attributes, a template's contents into
that document's inert one), clone (a template's contents with it),
`normalize`, the qualified names' validation and namespaces of
`createElementNS` and `setAttributeNS` (the 2025 rules: any name the parser
can make), `compareDocumentPosition`'s attributes and disconnected nodes.
Every change to a child list goes through insert and remove, every
attribute change through its one step: where mutation records and live
ranges will hook in.

Element creation is one path, the standard's "create an element", which
picks the element's class: `HTMLTemplateElement` (its `content`), and the
select, option and selectedcontent elements' own (their HTML behaviour:
an option's selectedness, a select's selectedcontent showing a copy of its
selected option, kept up as options and attributes change). Every other
element is an `Element`; HTML's other element classes come later.

The tree is linked siblings, no arrays per node; the collections are views
over it, read again after any change to the document's child lists or
attributes (a counter of its changes: a live collection's cache key).

Left out for now: events, Range, TreeWalker and NodeIterator,
MutationObserver, shadow DOM and custom elements, `querySelector` and
`matches` (selectors: helder.css), and the XML serializer (a document is
serialized as HTML).

## Serialization

`Dom.serialize(node)` is the HTML fragment serialization algorithm: an
element with its own tags (`outerHTML`), a document or fragment as its
children (`innerHTML`'s getter is an element's children). Attribute values
in double quotes, `&`, `<`, `>`, U+00A0 and `"` (in attributes) escaped,
void elements without an end tag, raw text elements' text as it is. As
the standard notes, a tree the parser made does not always come back the
same when its markup is parsed again (`<a><table><a>`, a `pre`'s first
newline); the round-trip property below keeps to the markup that does.

## Tests

- **Conformance** (the dom lane, natively; tests/dom/README.md):
  html5lib-tests' tokenizer tests (7,046 cases: tokens and the errors'
  codes and positions) and WPT's tree construction tests (1,959 cases),
  all passing; the 14 that need scripting on are skipped.
- **parse5** (the dom lane): 5,000 generated documents and the
  repository's pages parsed by helder and by parse5 (scripting off), the
  same tree but for parse5's known differences from today's standard
  (tests/dom/parse5-known.json).
- **Unit tests and properties** (`Dom.test.hx`, natively and as
  wasm32-wasi): the DOM's algorithms and their errors, collections,
  serialization; generated markup parsed, serialized and parsed again is
  the same tree; mutated pages parse without throwing, each within a
  bound of time and memory (also soaked by the fuzz lane).

## Speed

A parse is linear in its input, but for the scope checks of deeply nested
markup, which walk the open elements (as every implementation of the
algorithm does; a tag with no element open is answered from a count). The
tokenizer's text, attribute values and comments are found by a SIMD kernel
(`Scan.hx`: hxmc.simd over hxmc.rt.StrView's checked spans of the string),
tag and attribute names the parser knows are read straight from the input
(no copy, no hash), the tag tokens reused.

`bun run test bench html` (tests/bench/results/html.md, an Apple M-series
laptop): about 25 to 60 MB/s natively and 10 to 55 as wasm32-wasi, against
lexbor's 40 to 260 (C, the standard's algorithm) and @lukeed/html's 90 to
230 (JavaScript, not the standard's recovery).
