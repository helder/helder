# helder.syntax

Read and edit TypeScript, TSX and Haxe markup without running a compiler.
`Document.parse(text, Lang.of(path))` builds a concrete syntax tree that
keeps the source's whitespace and comments. Find markup by byte offset
or tag, or find a definition such as a `shader` or a `story` by name.

`Edits` changes attributes, children and object fields with a transaction.
Apply it to get the next document, or apply its inverse to undo it byte
for byte. Studio uses the same edits for the canvas and inspector.

See [Document.hx](Document.hx), [Edits.hx](Edits.hx) and the
[Studio README](../../../apps/studio/README.md).
