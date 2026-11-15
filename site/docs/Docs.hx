import Markdown;
import helder.syntax.Lexer;
import helder.syntax.Scanner.Lang;
import helder.view.*;
import helder.web.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The docs (docs/, `node site/build.mjs` builds them with the examples'
// pages): docs/index.md the overview (<out>/docs/index.html), each section
// of docs/docs.json a folder of Markdown pages (Markdown.hx), rendered here
// with helder.web's static renderer into <out>/docs/<section>/<page>/index.html
// (a section's index.md: <out>/docs/<section>/index.html):
// the site's top bar (its theme: site/build.mjs), a sidebar of every
// section's pages (on a phone, behind the top bar's menu, with the site's
// links), the previous and next pages; <out>/docs/search.json for
// static/docs.js' search. Built natively by site/build.mjs after the
// examples (their builds and the theme: bin/site-build/examples.json), then run:
//
//   <docs> <out>          (bin/site)
//
// A page's components: <Example id="..."/>, an example of examples/ or
// docs/examples/ (its id as the examples' page names it) played in the
// page, a WebAssembly island, with its source beside it, the file itself
// (highlighted by helder.syntax's lexer; tabs for a Haxe example's
// TypeScript twin, docs/examples/<dir>/main.ts); region="name" shows the
// lines between `// #region name` and `// #endregion` alone; <Sections/>,
// every section's pages with their first paragraphs (the overview's). An
// unknown example, region, component, page or heading link fails the
// build: what a page shows is what builds.
typedef Demo = {kind:String, width:Int, height:Int, onePixel:Bool};

typedef Example = {
	id:String,
	title:String,
	summary:String,
	tags:Array<String>,
	source:String,
	demo:Null<Demo>,
	wasm:String,
	imports:Array<String>,
	fonts:Array<String>,
	assets:String,
	args:Array<String>,
	file:String,
	alt:String,
	dir:String,
}

typedef Link = {id:String, label:String, href:String};
typedef Theme = {brand:String, home:String, nav:Array<Link>, action:Link, css:Array<String>, js:Array<String>, notice:String, footer:Array<Link>};
typedef SiteJson = {repository:String, examples:Array<Example>, theme:Theme};
typedef SectionJson = {id:String, title:String, pages:Array<String>};
typedef DocsJson = {sections:Array<SectionJson>};

class Page {
	public final section:SectionJson;
	public final id:String;
	public final file:String;
	// (from the site's root, as the pages' <base> has it)
	public final url:String;
	public final base:String;
	public final title:String;
	public final blocks:Array<Block>;
	public var prev:Null<Page> = null;
	public var next:Null<Page> = null;

	// (section null: the overview, docs/index.md)
	public function new(section:Null<SectionJson>, id:String) {
		this.section = section ?? {id: "", title: "Docs", pages: []};
		this.id = id;
		file = section == null ? 'docs/index.md' : 'docs/${section.id}/$id.md';
		// (a section's index.md its folder's page)
		url = section == null ? 'docs/' : id == "index" ? 'docs/${section.id}/' : 'docs/${section.id}/$id/';
		base = [for (_ in url.split("/").slice(1)) ".."].join("/") + "/";
		var all = Markdown.parse(File.getContent(file));
		switch all[0] {
			case Heading(1, _, c):
				title = Markdown.plain(c);
				blocks = all.slice(1);
			case _:
				throw '$file: a page starts with its title (# Title)';
		}
	}

	// its headings' ids, for links to them
	public function has(id:String):Bool {
		for (b in blocks)
			switch b {
				case Heading(_, i, _) if (i == id): return true;
				case _:
			}
		return false;
	}

	// its first paragraph (the overview's line for it)
	public function lede():Array<Inline> {
		for (b in blocks)
			switch b {
				case Para(c): return c;
				case _:
			}
		return [];
	}
}

class Docs implements Markup {
	static var repo = "";
	static var theme:Theme;
	static var conf:DocsJson;
	static var examples = new Map<String, Example>();
	static var pages:Array<Page> = [];
	static var current:Page;
	static final RUNNER = "static/helder/os/browser.mjs";
	static final HEADER = ~/^\/\/ *(title|summary|tags|demo|apk|data): /;

	static function main() {
		var out = Sys.args()[0];
		var site:SiteJson = haxe.Json.parse(File.getContent("bin/site-build/examples.json"));
		repo = site.repository;
		theme = site.theme;
		for (e in site.examples)
			examples.set(e.id, e);
		conf = haxe.Json.parse(File.getContent("docs/docs.json"));
		pages.push(new Page(null, "index"));
		for (s in conf.sections)
			for (p in s.pages)
				pages.push(new Page(s, p));
		for (k in 0...pages.length) {
			if (k > 0) pages[k].prev = pages[k - 1];
			if (k + 1 < pages.length) pages[k].next = pages[k + 1];
		}
		var search = [];
		for (p in pages) {
			current = p;
			Static.write(out + "/" + p.url + "index.html", Static.document(layout(p)));
			search.push({url: p.url, title: p.title, section: p.section.title,
				headings: [for (b in p.blocks) switch b {
					case Heading(2 | 3, id, c): {id: id, text: Markdown.plain(c)};
					case _: null;
				}].filter(h -> h != null), text: Markdown.text(p.blocks)});
		}
		File.saveContent(out + "/docs/search.json", haxe.Json.stringify(search));
		Sys.println('docs: ${pages.length} pages in $out/docs');
	}

	static function layout(p:Page):View {
		return <html lang="en">
			<head>
				<meta charset="utf-8"/>
				<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/>
				<base href={p.base}/>
				<title>{(p.section.id == "" ? "Docs" : p.title + " · " + p.section.title) + " · " + theme.brand}</title>
				<meta name="description" content={Markdown.plain(p.lede())}/>
				<link rel="stylesheet" href="static/site.css"/>
				{theme.css.map(h -> <link rel="stylesheet" href={h}/>)}
				<script src="static/stage.js" defer></script>
				<script src="static/loader.js" defer></script>
				<script src="static/docs.js" defer></script>
				{theme.js.map(h -> <script src={h} defer></script>)}
			</head>
			<body class="docs-page">
				{theme.notice == "" ? null : <div class="notice">{theme.notice}</div>}
				<header class="top"><div class="wrap">
					<button class="menu" type="button" aria-label="Pages" aria-controls="sidebar" aria-expanded="false">☰</button>
					<a class="brand" href={theme.home}>{theme.brand}</a>
					<nav aria-label="Site">{links()}</nav>
					<input class="search" type="search" placeholder="Search the docs" aria-label="Search the docs" autocomplete="off"/>
					{theme.action.label == "" ? null : <a class="btn" href={theme.action.href}>{theme.action.label}</a>}
					<ol class="results" hidden=""></ol>
				</div></header>
				<div class="wrap docs">
					<nav class="sidebar" id="sidebar" aria-label="Pages">
						<div class="links">{links()}</div>
						<ul><li><a href={pages[0].url} aria-current={p == pages[0] ? "page" : null}>Overview</a></li></ul>
						{conf.sections.map(s -> <section>
							<h2>{s.title}</h2>
							<ul>{pages.filter(q -> q.section.id == s.id).map(q -> <li>
								<a href={q.url} aria-current={q == p ? "page" : null}>{q.title}</a>
							</li>)}</ul>
						</section>)}
					</nav>
					<main class="article">
						{p.section.id == "" ? null : <p class="eyebrow">{p.section.title}</p>}
						<h1>{p.title}</h1>
						{p.blocks.map(block)}
						<nav class="pager" aria-label="Previous and next">
							{p.prev == null ? <span></span> : <a class="prev" href={p.prev.url}><small>Previous</small>{p.prev.title}</a>}
							{p.next == null ? <span></span> : <a class="next" href={p.next.url}><small>Next</small>{p.next.title}</a>}
						</nav>
						<p class="edit"><a href={repo + "/edit/main/" + p.file}>{"Edit " + p.file + " on GitHub"}</a></p>
					</main>
				</div>
				{theme.footer.length == 0 ? null : <footer class="foot"><div class="wrap">{theme.footer.map(l -> <a href={l.href}>{l.label}</a>)}</div></footer>}
			</body>
		</html>;
	}

	// the site's links (the top bar's; the sidebar's on a phone), Docs marked current
	static function links():Array<View>
		return theme.nav.map(l -> <a href={l.href} aria-current={l.id == "docs" ? "page" : null}>{l.label}</a>);

	static function block(b:Block):View {
		return switch b {
			case Heading(level, id, c):
				// (the page's own URL: the <base> is the site's root)
				var anchor = <a class="anchor" href={current.url + "#" + id} aria-hidden="true">#</a>;
				switch level {
					case 1 | 2: <h2 id={id}>{inlines(c)}{anchor}</h2>;
					case 3: <h3 id={id}>{inlines(c)}{anchor}</h3>;
					case _: <h4 id={id}>{inlines(c)}</h4>;
				}
			case Para(c): <p>{inlines(c)}</p>;
			case Code(lang, title, text): <div class="code">
				{title == "" ? null : <div class="name">{title}</div>}
				<pre data-lang={lang == "" ? null : lang}><code>{highlight(text, lang == "" ? title : lang)}</code></pre>
			</div>;
			case List(true, items): <ol>{items.map(item)}</ol>;
			case List(false, items): <ul>{items.map(item)}</ul>;
			case Quote(bs): <blockquote>{bs.map(block)}</blockquote>;
			case Rule: <hr/>;
			case Table(head, rows): <div class="table"><table>
				<thead><tr>{head.map(c -> <th>{inlines(c)}</th>)}</tr></thead>
				<tbody>{rows.map(r -> <tr>{r.map(c -> <td>{inlines(c)}</td>)}</tr>)}</tbody>
			</table></div>;
			case Component("Example", attrs): example(attrs);
			case Component("Sections", _): <ul class="toc">{conf.sections.map(s -> pages.filter(q -> q.section.id == s.id).map(q -> <li>
				<a href={q.url}>{q.title}</a><span>{Markdown.plain(q.lede())}</span>
			</li>))}</ul>;
			case Component(name, _): throw '${current.file}: <$name> is no component (Example, Sections)';
		}
	}

	// a list item: a lone paragraph's text without the <p>
	static function item(bs:Array<Block>):View
		return switch bs {
			case [Para(c)]: <li>{inlines(c)}</li>;
			case _: <li>{bs.map(block)}</li>;
		}

	static function inlines(c:Array<Inline>):Array<Any>
		return c.map(span);

	static function span(n:Inline):Any
		return switch n {
			case Text(t): t;
			case CodeSpan(t): <code>{t}</code>;
			case Strong(c): <strong>{inlines(c)}</strong>;
			case Em(c): <em>{inlines(c)}</em>;
			case Link(href, c): <a href={link(href)}>{inlines(c)}</a>;
		}

	// a page's link: another page (world.md, ../scene/world.md#fog) as its
	// URL, its heading checked; a heading of this page (#fog); a path in the
	// repository (/src/helder/asset/README.md) on GitHub; a URL as it is
	static function link(href:String):String {
		if (~/^[a-z]+:/.match(href)) return href;
		var hash = href.indexOf("#");
		var path = hash < 0 ? href : href.substr(0, hash), anchor = hash < 0 ? "" : href.substr(hash + 1);
		if (path == "") {
			if (!current.has(anchor)) throw '${current.file}: $href: no such heading in the page';
			return current.url + "#" + anchor;
		}
		if (path.startsWith("/")) {
			if (!FileSystem.exists(path.substr(1))) throw '${current.file}: $href: no such file in the repository';
			return repo + "/tree/main" + path + (anchor == "" ? "" : "#" + anchor);
		}
		if (path.endsWith(".md")) {
			var target = haxe.io.Path.normalize(haxe.io.Path.directory(current.file) + "/" + path);
			for (p in pages)
				if (p.file == target) {
					if (anchor != "" && !p.has(anchor)) throw '${current.file}: $href: no such heading in ${p.file}';
					return p.url + (anchor == "" ? "" : "#" + anchor);
				}
			throw '${current.file}: $href: no such page in docs/docs.json';
		}
		throw '${current.file}: $href: a link is a page (.md), a path from the repository\'s root (/...) or a URL';
	}

	// --- examples

	static function example(attrs:Map<String, String>):View {
		var id = attrs.get("id");
		var e = examples.get(id);
		if (e == null) throw '${current.file}: <Example id="$id"/>: no such example (examples/ or docs/examples/, with a header)';
		var region = attrs.get("region");
		// (file: another of its directory's files shown, not its entry)
		var shown = attrs.exists("file") ? e.dir + "/" + attrs.get("file") : e.file;
		if (!FileSystem.exists(shown)) throw '${current.file}: <Example id="$id" file="${attrs.get("file")}"/>: no $shown';
		var files = [shown].concat(e.alt == "" ? [] : [e.alt]);
		var sources = [for (k in 0...files.length) {file: files[k], text: source(files[k], k == 0 ? region : null)}];
		var run = "helder run " + e.file;
		return <figure class="example" id={"example-" + e.id}>
			{e.demo == null ? null : stage(e)}
			<figcaption>
				<strong>{e.title}</strong>{" " + e.summary}
				<span class="run"><code>{run}</code> · <a href={e.source}>Source</a></span>
			</figcaption>
			<div class="sources">
				<div class="tabs" role="tablist">{sources.map(s -> <button type="button" role="tab" aria-selected={s.file == files[0] ? "true" : "false"}
					data-file={s.file}>{haxe.io.Path.withoutDirectory(s.file)}{s.file.endsWith(".ts") || s.file.endsWith(".tsx") ? " (TypeScript)" : " (Haxe)"}</button>)}</div>
				{sources.map(s -> <div class="code" data-file={s.file} hidden={s.file != files[0]}><pre><code>{highlight(s.text, s.file)}</code></pre></div>)}
			</div>
		</figure>;
	}

	// a file as a page shows it: without its header (the examples' page's
	// title, summary, tags, demo) or the region markers; a region alone when named
	static function source(file:String, region:Null<String>):String {
		var lines = File.getContent(file).replace("\r\n", "\n").split("\n");
		var start = 0;
		while (start < lines.length && HEADER.match(lines[start]))
			start++;
		lines = lines.slice(start);
		if (region != null) {
			// (several: region="a,b", each in turn, "// ..." between them)
			var picked = [];
			for (name in region.split(",").map(s -> s.trim())) {
				var from = -1, to = -1;
				for (k in 0...lines.length) {
					var t = lines[k].trim();
					if (from < 0 && t == "// #region " + name) from = k + 1;
					else if (from >= 0 && to < 0 && t == "// #endregion") to = k;
				}
				if (from < 0 || to < 0) throw '${current.file}: region="$name": $file has no `// #region $name` ... `// #endregion`';
				var part = lines.slice(from, to);
				// (its common indentation taken off)
				var cut = 1000;
				for (l in part)
					if (l.trim() != "") {
						var n = 0;
						while (n < l.length && l.charAt(n) == "\t")
							n++;
						if (n < cut) cut = n;
					}
				if (picked.length > 0) picked.push("// ...");
				for (l in part)
					picked.push(l.substr(cut == 1000 ? 0 : cut));
			}
			lines = picked;
		}
		lines = lines.filter(l -> !~/^\s*\/\/ #(region|endregion)\b/.match(l));
		while (lines.length > 0 && lines[0].trim() == "")
			lines.shift();
		while (lines.length > 0 && lines[lines.length - 1].trim() == "")
			lines.pop();
		return lines.join("\n");
	}

	// the example's canvas and Play button: a WebAssembly island loaded on
	// the first click, stopped once scrolled out of view (site/stage.js: full screen)
	static function stage(e:Example):View {
		var d = e.demo;
		var sound = d.kind == "sound";
		return <div class={sound ? "stage sound" : "stage"} style={sound ? "" : "--w:" + d.width + "px;--ratio:" + d.width + "/" + d.height}
			data-width={"" + d.width} data-height={"" + d.height} data-one-pixel={d.onePixel ? "" : null}>
			<Island.Wasm src={e.wasm} id={"play-" + e.id} load={Click} runner={RUNNER} imports={e.imports} fonts={e.fonts}
				assets={e.assets == "" ? null : e.assets} args={e.args.length > 0 ? e.args : null} stop={Offscreen} canvas={!sound} width={d.width} height={d.height}>
				<button class="play" type="button" aria-label={"Play " + e.title}>{sound ? "▶ Play sound" : "▶ Play"}</button>
			</Island.Wasm>
			{sound ? null : <button class="full" type="button" aria-label={"Play " + e.title + " full screen"}>⛶ Full screen</button>}
			{sound ? null : <button class="exit" type="button" aria-label="Leave full screen">✕</button>}
		</div>;
	}

	// --- highlighting: helder.syntax's lexer (the code editor's), a span a token

	static function highlight(text:String, lang:String):Array<Any> {
		var l = lang.toLowerCase();
		var language:Null<Lang> = if (l == "haxe" || l == "hx" || l.endsWith(".hx")) Haxe
			else if (l == "tsx" || l.endsWith(".tsx")) Tsx
			else if (l == "ts" || l == "typescript" || l == "js" || l == "javascript" || l.endsWith(".ts") || l.endsWith(".mjs") || l.endsWith(".js")) Ts
			else null;
		if (language == null) return [text];
		var lexer = new Lexer(language);
		var state = lexer.start();
		var out:Array<Any> = [];
		var tokens = [];
		var lines = text.split("\n");
		for (k in 0...lines.length) {
			var line = lines[k];
			tokens.resize(0);
			state = lexer.line(line, state, tokens);
			var at = 0, i = 0;
			while (i < tokens.length) {
				var s = tokens[i], e = tokens[i + 1], cls:TokenClass = tokens[i + 2];
				if (s > at) out.push(line.substring(at, s));
				if (cls == Plain || cls == Punct) out.push(line.substring(s, e)) else out.push(token(cls.name(), line.substring(s, e)));
				at = e;
				i += 3;
			}
			if (at < line.length) out.push(line.substr(at));
			if (k + 1 < lines.length) out.push("\n");
		}
		// (adjacent texts as one)
		var merged:Array<Any> = [];
		var buf = new StringBuf(), any = false;
		for (x in out)
			if (Std.isOfType(x, String)) {
				buf.add((x : String));
				any = true;
			} else {
				if (any) merged.push(buf.toString());
				buf = new StringBuf();
				any = false;
				merged.push(x);
			}
		if (any) merged.push(buf.toString());
		return merged;
	}

	static function token(cls:String, text:String):View
		return <span class={"t-" + cls}>{text}</span>;
}
