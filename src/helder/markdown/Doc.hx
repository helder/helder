package helder.markdown;

// A Markdown document as Markdown.parse reads it: its blocks, and its
// front matter's text (the lines between a "---" first line and the next
// "---" or "...", unparsed; null: none)
typedef Doc = {
	blocks:Array<Block>,
	frontMatter:Null<String>
}

enum Block {
	// level 1 to 6; id: its text as a slug (GitHub's: "Set up" is
	// set-up), unique in the document (a second one set-up-1)
	Heading(level:Int, id:String, content:Array<Inline>);
	Paragraph(content:Array<Inline>);
	// start: an ordered list's first number; tight: no blank lines between its items (their paragraphs shown without spacing)
	List(ordered:Bool, start:Int, tight:Bool, items:Array<ListItem>);
	Quote(blocks:Array<Block>);
	// fenced or indented; info: what follows the opening fence ("ts", "" for none), text: its lines, each ending in "\n"
	Code(info:String, text:String);
	// GFM's: each column's alignment, the header's cells, the rows' (as many as the header's)
	Table(align:Array<TableAlign>, head:Array<Array<Inline>>, rows:Array<Array<Array<Inline>>>);
	Rule;
	// a raw HTML block, kept as its text
	Html(text:String);
}

// an item's blocks; task: a GFM task's state ([x] true, [ ] false; null: not a task)
typedef ListItem = {
	blocks:Array<Block>,
	task:Null<Bool>
}

enum abstract TableAlign(String) to String {
	var Auto = "auto";
	var Left = "left";
	var Center = "center";
	var Right = "right";
}

enum Inline {
	Text(text:String);
	Emphasis(content:Array<Inline>);
	Strong(content:Array<Inline>);
	Strike(content:Array<Inline>);
	CodeSpan(text:String);
	// href as written, its escapes and entities resolved (not percent-encoded); title: "" for none
	Link(href:String, title:String, content:Array<Inline>);
	// alt: the description's plain text
	Image(src:String, alt:String, title:String);
	// <https://x.org>, <me@x.org>, and GFM's www.x.org, https://x.org and me@x.org in text: href (mailto: for an address, http:// for www.) and the text shown
	Autolink(href:String, text:String);
	SoftBreak;
	HardBreak;
	// raw inline HTML, kept as its text
	Html(text:String);
}
