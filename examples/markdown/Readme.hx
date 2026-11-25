// title: Markdown
// summary: helder.markdown: a CommonMark and GFM document parsed and shown, headings, lists, a table, code highlighted, links followed
// tags: ui, text, markdown
// demo: canvas 760x640
import helder.markdown.Markdown;
import helder.markdown.MarkdownView;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;

// A Markdown document (the file given, else the one below) in a window, in
// MarkdownView's plain look: a link to a heading ("#...") scrolls to it,
// others are printed
class Readme implements Markup {
	static function main() {
		var text = SAMPLE;
		#if sys
		var args = Sys.args();
		if (args.length > 0) text = sys.io.File.getContent(args[0]);
		#end
		var view:Null<MarkdownView> = null;
		view = new MarkdownView({
			doc: Markdown.parse(text),
			onLink: href -> if (StringTools.startsWith(href, "#")) view.scrollToHeading(href.substr(1)) else trace(href)
		});
		UiWindow.run(<Surface title="Markdown" width={760} height={640}><view flexGrow={1} background="#ffffff" color="#1f2328">{view}</view></Surface>);
	}

	static final SAMPLE = "# helder.markdown

CommonMark with GitHub's tables, task lists, ~~strikethrough~~ and
autolinks like www.example.com, parsed into a plain tree and shown here
*unstyled*: the look is the app's. See [the code](#code) below.

## A list

1. Parse with `Markdown.parse(text)`
2. Show with **MarkdownView**
   - nested items
   - [x] and tasks
   - [ ] still to do

> A quote, with a [link](https://commonmark.org) in it.

## A table

| Feature | Where | Notes |
|:--|:-:|--:|
| Blocks | Blocks.hx | CommonMark's |
| Inlines | Inlines.hx | delimiter runs |
| Tables | GFM | aligned |

## Code

```ts
const doc = Markdown.parse(\"# Hello\");
console.log(doc.blocks.length);
```

---

That's all.
";
}
