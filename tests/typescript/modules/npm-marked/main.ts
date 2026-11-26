// A real package: marked 15.0.12 (MIT, its LICENSE.md beside it), its
// lib/marked.esm.js and lib/marked.d.ts as published (its inline rules:
// \p{P} and \p{S}, at module init)
import {marked} from "marked";

const doc = `# Hello, *helder*

Some **strong**, _emphasis_ and \`code\`; a [link](https://helder.build "home").

- one
- two
  1. nested
  2. list

> a quote, with ~~strike~~

| a | b |
|---|--:|
| 1 | 2 |

\`\`\`ts
const x = 1 < 2;
\`\`\`

Punctuation: ¡olé! «quoted» — dash…
`;
console.log(marked.parse(doc, {async: false}));
console.log(marked.parseInline("an *inline* «run»", {async: false}));
console.log(marked.lexer("# h\n\ntext").map(t => t.type).join(","));
