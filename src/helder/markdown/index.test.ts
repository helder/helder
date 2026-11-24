// helder/markdown from TypeScript (the test lane: natively and as
// wasm32-wasi): a document parsed, its front matter, its headings' ids, a
// view of it.
import { describe, test, assert, equals } from "helder/test";
import { Markdown, MarkdownView } from "helder/markdown";

describe("helder/markdown", () => {
	test("a document parsed and viewed", () => {
		const doc = Markdown.parse("---\ntitle: x\n---\n# Hello there\n\nSome *text*.\n\n## Again\n");
		equals(doc.frontMatter, "title: x\n");
		equals(doc.blocks.length, 3);
		equals(Markdown.slug("Set up, again!"), "set-up-again");
		const view = new MarkdownView({ doc, onLink: href => console.log(href) });
		equals(view.headings(), ["hello-there", "again"]);
		assert(view.scroller !== null);
		equals(new MarkdownView({ doc, scroll: false, blocks: 1 }).scroller, null);
	});
});
