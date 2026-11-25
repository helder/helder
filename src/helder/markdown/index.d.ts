// helder.markdown for TypeScript programs (helder.typescript): Markdown.parse
// (a Doc: its blocks are Haxe's enums, given to MarkdownView as they are),
// slug, and MarkdownView, a document as nodes in helder/ui's tree.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Node} from "helder/ui";

declare const __haxe: {Markdown: "helder.markdown.Markdown", MarkdownView: "helder.markdown.MarkdownView", __module: "helder.markdown.TypeScript"};

// A Markdown document as Markdown.parse reads it: its blocks, and its
// front matter's text (the lines between a "---" first line and the next
// "---" or "...", unparsed; null: none)
export type Doc = { blocks: unknown[]; frontMatter: string | null };

export type MarkdownProps = { doc: Doc; onLink?: (href: string) => void; image?: (src: string, alt: string) => Node | null; scroll?: boolean; blocks?: number; codeFont?: string; codeSize?: number };

// Markdown as CommonMark reads it (0.31: its block structure, inline
// rules, entities, reference definitions) with GFM's tables, task list
// items, strikethrough and extended autolinks; raw HTML kept as text
// (Html blocks and inlines), a front matter's text taken off the top.
//
//   var doc = Markdown.parse(File.getContent("README.md"));
//   for (b in doc.blocks) switch b {
//     case Heading(level, id, content): trace(level, Markdown.plain(content));
//     case _:
//   }
export declare class Markdown {
	// containers (quotes, lists' items) and inlines nested deeper are text (markdown-it's limit too)
	static readonly MAX_NESTING: number;
	static parse(text: string): Doc;
	// the text of inlines, without their markup (an image's its alt)
	static plain(content: unknown[]): string;
	// a heading's id from its text, as GitHub makes it: lower case, spaces as
	// hyphens, punctuation but - and _ left out ("Set up, again!" is set-up-again)
	static slug(text: string): string;
}

// A Markdown document (Markdown.parse's Doc) as nodes, unstyled: each part
// has a slot that the app's look styles (a Look's parts, a StyleSheet's
// rules; without a sheet the base rules here give a plain default). The
// top-level blocks are each in a row ("markdown-row": the column's width
// and the space between blocks), in a scroller ("markdown-scroll"), a
// VirtualScroll past VIRTUAL blocks (only the rows in view made). Slots:
// markdown-h1 to -h6, -p, -quote, -list (data-tight when tight),
// -item, -marker, -task (data-state checked or unchecked), -item-body,
// -code (a box around a read-only CodeView: the fence's language by its
// info string, CodeLanguages; plain text otherwise), -table, -th, -td,
// -rule, -html (raw HTML, as text), -image-alt; in text -em, -strong,
// -del, -code-span, -link. Links call onLink; images ask image for a node.
// It is one selectable scope (Node.selectable): a selection runs across
// its blocks, a long document's rows out of view too, copied with a blank
// line between blocks and a line between list items (markers not in it).
// Spacing between nested blocks is their container's row-gap (a quote's,
// an item body's, a list's).
export declare class MarkdownView extends Node {
	constructor(props: MarkdownProps);
	static readonly VIRTUAL: number;
	readonly doc: Doc;
	// the scroller (a VirtualScroll past VIRTUAL blocks; null with scroll false)
	readonly scroller: Node | null;
	// the heading with this id (a link's "#id", Markdown.slug's) brought to the view's top; false: none
	scrollToHeading(id: string): boolean;
	// the headings' ids, in order
	headings(): string[];
}

export {};
