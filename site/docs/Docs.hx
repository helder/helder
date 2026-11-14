import Markdown;
import helder.syntax.Lexer;
import helder.syntax.Scanner.Lang;
import helder.view.*;
import helder.web.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The docs (docs/, `node site/build.mjs` builds them with the examples'
// page): each section of docs/docs.json a folder of Markdown pages
// (Markdown.hx), rendered here with helder.web's static renderer into
// <out>/docs/<section>/<page>.html, a sidebar of every section's pages,
// the page's headings, the previous and next pages; <out>/docs/search.json
// for docs.js' search. Built natively by site/build.mjs after the examples
// (their builds: bin/site-build/examples.json), then run:
//
//   <docs> <out>          (bin/site)
//
// A page's components: <Example id="..."/>, an example of examples/ or
// docs/examples/ (its id as the examples' page names it) played in the
// page, a WebAssembly island, with its source beside it, the file itself
// (highlighted by helder.syntax's lexer; tabs for a Haxe example's
// TypeScript twin, docs/examples/<dir>/main.ts); region="name" shows the
// lines between `// #region name` and `// #endregion` alone. An unknown
// example, region, component or page link fails the build: what a page
// shows is what builds.
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

typedef SiteJson = {repository:String, examples:Array<Example>};
typedef SectionJson = {id:String, title:String, pages:Array<String>};
typedef DocsJson = {sections:Array<SectionJson>};

class Page {
	public final section:SectionJson;
	public final id:String;
	public final file:String;
	public final url:String;
	public final title:String;
	public final blocks:Array<Block>;
	public var prev:Null<Page> = null;
	public var next:Null<Page> = null;

	public function new(section:SectionJson, id:String) {
		this.section = section;
		this.id = id;
		file = 'docs/${section.id}/$id.md';
		url = 'docs/${section.id}/$id.html';
		var all = Markdown.parse(File.getContent(file));
		switch all[0] {
			case Heading(1, _, c):
				title = Markdown.plain(c);
				blocks = all.slice(1);
			case _:
				throw '$file: a page starts with its title (# Title)';
		}
	}
}

class Docs implements Markup {
	static var repo = "";
	static var examples = new Map<String, Example>();
	static var pages:Array<Page> = [];
	static var current:Page;
	static final RUNNER = "helder/os/browser.mjs";
	static final HEADER = ~/^\/\/ *(title|summary|tags|demo|apk|data): /;

	static function main() {
		var out = Sys.args()[0];
		var site:SiteJson = haxe.Json.parse(File.getContent("bin/site-build/examples.json"));
		repo = site.repository;
		for (e in site.examples)
			examples.set(e.id, e);
		var conf:DocsJson = haxe.Json.parse(File.getContent("docs/docs.json"));
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
			Static.write(out + "/" + p.url, Static.document(layout(conf, p)));
			search.push({url: p.url, title: p.title, section: p.section.title,
				headings: [for (b in p.blocks) switch b {
					case Heading(2 | 3, id, c): {id: id, text: Markdown.plain(c)};
					case _: null;
				}].filter(h -> h != null), text: Markdown.text(p.blocks)});
		}
		File.saveContent(out + "/docs/search.json", haxe.Json.stringify(search));
		// (docs/: the first page)
		Static.write(out + "/docs/index.html", Static.document(<html lang="en">
			<head>
				<meta charset="utf-8"/>
				<meta http-equiv="refresh" content={"0; url=../" + pages[0].url}/>
				<title>helder docs</title>
			</head>
			<body><p><a href={"../" + pages[0].url}>{pages[0].title}</a></p></body>
		</html>));
		Sys.println('docs: ${pages.length} pages in $out/docs');
	}

	static function layout(conf:DocsJson, p:Page):View {
		var toc = [for (b in p.blocks) switch b {
			case Heading(2, id, c): <li><a href={"#" + id}>{Markdown.plain(c)}</a></li>;
			case _: null;
		}].filter(v -> v != null);
		return <html lang="en">
			<head>
				<meta charset="utf-8"/>
				<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/>
				<base href="../../"/>
				<title>{p.title + " · " + p.section.title + " · helder docs"}</title>
				<link rel="stylesheet" href="docs/docs.css"/>
				<script src="stage.js" defer></script>
				<script src="loader.js" defer></script>
				<script src="docs/docs.js" defer></script>
			</head>
			<body>
				<header class="top">
					<button class="menu" type="button" aria-label="Pages" aria-controls="sidebar" aria-expanded="false">☰</button>
					<a class="brand" href={pages[0].url}>helder <span>docs</span></a>
					<input class="search" type="search" placeholder="Search the docs" aria-label="Search the docs" autocomplete="off"/>
					<nav class="links"><a href="index.html">Examples</a><a href={repo}>GitHub</a></nav>
					<ol class="results" hidden=""></ol>
				</header>
				<div class="shell">
					<nav class="sidebar" id="sidebar" aria-label="Pages">
						{conf.sections.map(s -> <section>
							<h2>{s.title}</h2>
							<ul>{pages.filter(q -> q.section.id == s.id).map(q -> <li>
								<a href={q.url} aria-current={q == p ? "page" : null}>{q.title}</a>
							</li>)}</ul>
						</section>)}
					</nav>
					<main class="article">
						<p class="crumb">{p.section.title}</p>
						<h1>{p.title}</h1>
						{p.blocks.map(block)}
						<nav class="pager" aria-label="Previous and next">
							{p.prev == null ? <span></span> : <a class="prev" href={p.prev.url}><small>Previous</small>{p.prev.title}</a>}
							{p.next == null ? <span></span> : <a class="next" href={p.next.url}><small>Next</small>{p.next.title}</a>}
						</nav>
						<p class="edit"><a href={repo + "/edit/main/" + p.file}>{"Edit " + p.file}</a></p>
					</main>
					<aside class="toc" aria-label="On this page">
						{toc.length > 1 ? <h2>On this page</h2> : null}
						{toc.length > 1 ? <ul>{toc}</ul> : null}
					</aside>
				</div>
			</body>
		</html>;
	}

	static function block(b:Block):View {
		return switch b {
			case Heading(level, id, c):
				var anchor = <a class="anchor" href={"#" + id} aria-hidden="true">#</a>;
				switch level {
					case 1 | 2: <h2 id={id}>{inlines(c)}{anchor}</h2>;
					case 3: <h3 id={id}>{inlines(c)}{anchor}</h3>;
					case _: <h4 id={id}>{inlines(c)}</h4>;
				}
			case Para(c): <p>{inlines(c)}</p>;
			case Code(lang, text): <pre class="code" data-lang={lang == "" ? null : lang}><code>{highlight(text, lang)}</code></pre>;
			case List(true, items): <ol>{items.map(item)}</ol>;
			case List(false, items): <ul>{items.map(item)}</ul>;
			case Quote(bs): <blockquote>{bs.map(block)}</blockquote>;
			case Rule: <hr/>;
			case Table(head, rows): <div class="table"><table>
				<thead><tr>{head.map(c -> <th>{inlines(c)}</th>)}</tr></thead>
				<tbody>{rows.map(r -> <tr>{r.map(c -> <td>{inlines(c)}</td>)}</tr>)}</tbody>
			</table></div>;
			case Component("Example", attrs): example(attrs);
			case Component(name, _): throw '${current.file}: <$name> is no component (Example)';
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
	// HTML, a path in the repository (/src/helder/asset/README.md) on GitHub,
	// a URL or an anchor as it is
	static function link(href:String):String {
		if (href.startsWith("#") || ~/^[a-z]+:/.match(href)) return href;
		var hash = href.indexOf("#");
		var path = hash < 0 ? href : href.substr(0, hash), anchor = hash < 0 ? "" : href.substr(hash);
		if (path.startsWith("/")) {
			if (!FileSystem.exists(path.substr(1))) throw '${current.file}: $href: no such file in the repository';
			return repo + "/tree/main" + path + anchor;
		}
		if (path.endsWith(".md")) {
			var target = haxe.io.Path.normalize('docs/${current.section.id}/$path');
			for (p in pages)
				if (p.file == target) return p.url + anchor;
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
				{sources.map(s -> <pre class="code" data-file={s.file} hidden={s.file != files[0]}><code>{highlight(s.text, s.file)}</code></pre>)}
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
