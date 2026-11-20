import Markdown;
import helder.syntax.Lexer;
import helder.syntax.Scanner.Lang;
import helder.view.*;
import helder.web.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The docs (docs/, `node site/build.mjs` builds them with the examples'
// pages): docs/index.md the introduction (<out>/docs/index.html), then each
// group of docs/docs.json a folder of Markdown pages (Markdown.hx) rendered
// with helder.web's static renderer into <out>/docs/<group>/<page>/index.html.
// A page id with a slash ("3d/models") is a sub-page, indented under its
// parent in the sidebar. Around each page: the site's top bar (its theme:
// site/build.mjs), the sidebar of the groups (on a phone behind the top
// bar's menu, with the site's links), the previous and next pages;
// <out>/docs/search.json for static/docs.js' search; docs.json's `moved`,
// old addresses sent on to their pages. Built natively by site/build.mjs
// after the examples (their builds and the theme: bin/site-build/examples.json):
//
//   <docs> <out>          (bin/site)
//
// Components, a line alone in a page:
//   <Example id="..."/>          an example of examples/ or docs/examples/
//                                live in the page (a WebAssembly island,
//                                started once in view); region="a,b" shows
//                                those lines of its source (`// #region a`
//                                ... `// #endregion`), its TypeScript twin's
//                                beside them
//   <Image src="x.webp" alt=""/> a picture of site/visuals (site/visuals.mjs)
//   <Terminal src="help.txt"/>   a command's output, of site/visuals
//   <Platforms/>                 where an app runs and ships
//   <Reference to="ui,view"/>    the packages' READMEs: every function
//   <Sections/>                  every group and its pages
// Two fences in a row, TypeScript and Haxe, are one sample in two tabs. An
// unknown example, region, picture, component, page or heading link fails
// the build: what a page shows is what builds.
typedef Demo = {kind:String, width:Int, height:Int, onePixel:Bool};

typedef Example = {
	id:String,
	title:String,
	summary:String,
	tags:Array<String>,
	source:String,
	demo:Null<Demo>,
	poster:String,
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
typedef DocsJson = {sections:Array<SectionJson>, moved:Dynamic};

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

	// (section null: the introduction, docs/index.md)
	public function new(section:Null<SectionJson>, id:String) {
		this.section = section ?? {id: "", title: "Docs", pages: []};
		this.id = id;
		file = section == null ? 'docs/index.md' : 'docs/${section.id}/$id.md';
		url = section == null ? 'docs/' : 'docs/${section.id}/$id/';
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

	public var sub(get, never):Bool;

	function get_sub()
		return id.indexOf("/") > 0;

	public function has(id:String):Bool {
		for (b in blocks)
			switch b {
				case Heading(_, i, _) if (i == id): return true;
				case _:
			}
		return false;
	}

	// its first paragraph: what and why
	public function lede():Array<Inline> {
		for (b in blocks)
			switch b {
				case Para(c): return c;
				case _:
			}
		return [];
	}

	public function headings():Array<{id:String, level:Int, text:String}> {
		return [for (b in blocks) switch b {
			case Heading(level, id, c) if (level == 2 || level == 3): {id: id, level: level, text: Markdown.plain(c)};
			case _: null;
		}].filter(h -> h != null);
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
	static final VISUALS = "site/visuals/";

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
				headings: p.headings(), text: Markdown.text(p.blocks)});
		}
		File.saveContent(out + "/docs/search.json", haxe.Json.stringify(search));
		// (the old addresses, linked from elsewhere: a page that sends on)
		var moved = conf.moved == null ? [] : Reflect.fields(conf.moved);
		for (from in moved) {
			var to:String = Reflect.field(conf.moved, from);
			var page = pages.filter(p -> p.url == 'docs/$to/' || (to == "" && p.url == "docs/"));
			if (page.length == 0) throw 'docs/docs.json: moved $from to $to: no such page';
			var depth = [for (_ in 'docs/$from/'.split("/").slice(1)) ".."].join("/") + "/";
			FileSystem.createDirectory(out + '/docs/$from');
			File.saveContent(out + '/docs/$from/index.html', '<!doctype html>\n<meta charset="utf-8">\n<title>${page[0].title}</title>\n'
				+ '<link rel="canonical" href="$depth${page[0].url}">\n<meta http-equiv="refresh" content="0; url=$depth${page[0].url}">\n'
				+ '<a href="$depth${page[0].url}">${page[0].title}</a>\n');
		}
		Home.write(out, theme, examples, repo);
		Sys.println('docs: ${pages.length} pages, ${moved.length} moved, in $out/docs; the landing, $out/index.html');
	}

	static function layout(p:Page):View {
		var intro = p == pages[0];
		return <html lang="en">
			<head>
				<meta charset="utf-8"/>
				<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/>
				<base href={p.base}/>
				<title>{(intro ? "Documentation" : p.title) + " · " + theme.brand}</title>
				<meta name="description" content={Markdown.plain(p.lede())}/>
				<link rel="stylesheet" href="static/site.css"/>
				{theme.css.map(h -> <link rel="stylesheet" href={h}/>)}
				<script src="static/docs.js" defer></script>
				<script src="static/stage.js" defer></script>
				<script src="static/loader.js" defer></script>
				{theme.js.map(h -> <script src={h} defer></script>)}
			</head>
			<body class="docs-page">
				<a class="skip" href={p.url + "#docs-main"}>Skip to content</a>
				{theme.notice == "" ? null : <div class="notice">{theme.notice}</div>}
				<header class="top"><div class="wrap">
					<button class="menu" type="button" aria-label="Documentation menu" aria-controls="sidebar" aria-expanded="false"><span></span></button>
					<a class="brand" href={theme.home}>{theme.brand}</a>
					<nav aria-label="Site">{links()}</nav>
					<input class="search" type="search" placeholder="Search" aria-label="Search the docs" aria-controls="search-results" aria-keyshortcuts="/" autocomplete="off"/>
					<ol class="results" id="search-results" aria-label="Search results" hidden=""></ol>
					<span class="visually-hidden" id="search-status" role="status"></span>
					{theme.action.label == "" ? null : <a class="btn" href={theme.action.href}>{theme.action.label}</a>}
				</div></header>
				<div class="wrap docs">
					<nav class="sidebar" id="sidebar" aria-label="Pages">
						<div class="links">{links()}</div>
						{conf.sections.map(s -> <section>
							<h2>{s.title}</h2>
							<ul>{(s == conf.sections[0] ? [pages[0]] : []).concat(pages.filter(q -> q.section.id == s.id)).map(q -> <li class={q.sub ? "sub" : null}>
								<a href={q.url} aria-current={q == p ? "page" : null}>{q.title}</a>
							</li>)}</ul>
						</section>)}
					</nav>
					<main class="article" id="docs-main" tabindex="-1">
						<p class="eyebrow">{intro ? "Start" : p.section.title}</p>
						<h1>{p.title}</h1>
						{p.blocks.map(block)}
						<nav class="pager" aria-label="Previous and next">
							{p.prev == null ? <span></span> : <a class="prev" href={p.prev.url}><small>← Previous</small>{p.prev.title}</a>}
							{p.next == null ? <span></span> : <a class="next" href={p.next.url}><small>Next →</small>{p.next.title}</a>}
						</nav>
						<p class="edit"><a href={repo + "/edit/main/" + p.file}>Edit this page</a></p>
					</main>
				</div>
				{theme.footer.length == 0 ? null : <footer class="foot"><div class="wrap">{theme.footer.map(l -> <a href={l.href}>{l.label}</a>)}</div></footer>}
			</body>
		</html>;
	}

	// the site's links (the top bar's; the sidebar's on a phone), Docs marked current
	static function links():Array<View>
		return theme.nav.map(l -> <a href={l.href} aria-current={l.id == "docs" ? "page" : null}>{l.label}</a>);

	// a sample in one language: which, for a reader of the other
	static function label(lang:String):View
		return <div class="switch"><span class="only">{Markdown.family(lang) == "ts" ? "TypeScript" : "Haxe"}</span></div>;

	static function copy():View
		return <button type="button" class="copy-code" aria-label="Copy code" hidden="">Copy</button>;

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
				{title == "" && lang != "sh" && Markdown.family(lang) == null ? copy() : <div class="name">
					{title == "" && lang != "sh" ? label(lang) : <span>{title == "" ? "Terminal" : title}</span>}{copy()}
				</div>}
				<pre data-lang={lang == "" ? null : lang}><code>{highlight(text, lang == "" ? title : lang)}</code></pre>
			</div>;
			case Langs(codes): langs([for (c in codes) switch c {
				case Code(lang, title, text): {lang: lang, title: title, text: text};
				case _: throw "unreachable";
			}]);
			case List(true, items): <ol>{items.map(item)}</ol>;
			case List(false, items): <ul>{items.map(item)}</ul>;
			case Quote(bs): <blockquote>{bs.map(block)}</blockquote>;
			case Rule: <hr/>;
			case Table(head, rows): <div class="table"><table>
				<thead><tr>{head.map(c -> <th scope="col">{inlines(c)}</th>)}</tr></thead>
				<tbody>{rows.map(r -> <tr>{r.map(c -> <td>{inlines(c)}</td>)}</tr>)}</tbody>
			</table></div>;
			case Component("Example", attrs): example(attrs);
			case Component("Image", attrs): image(attrs);
			case Component("Terminal", attrs): terminal(attrs);
			case Component("Platforms", _): platforms();
			case Component("Reference", attrs): reference(attrs.get("to"));
			case Component("Sections", _): sections();
			case Component(name, _): throw '${current.file}: <$name> is no component (Example, Image, Terminal, Platforms, Reference, Sections)';
		}
	}

	// one sample in TypeScript and Haxe: a tab each, the reader's choice
	// remembered (static/docs.js), TypeScript first
	public static function langs(codes:Array<{lang:String, title:String, text:String}>):View {
		codes.sort((a, b) -> Markdown.family(a.lang) == "ts" ? -1 : 1);
		return <div class="code langs">
			<div class="name">
				<div class="switch" role="tablist" aria-label="Language">{codes.map(c -> <button type="button" role="tab" data-lang={Markdown.family(c.lang)}
					aria-selected={c == codes[0] ? "true" : "false"}>{Markdown.family(c.lang) == "ts" ? "TypeScript" : "Haxe"}</button>)}</div>
				{copy()}
			</div>
			{codes.map(c -> <pre data-lang={Markdown.family(c.lang)} hidden={c != codes[0]}><code>{highlight(c.text, c.lang)}</code></pre>)}
		</div>;
	}

	static function sections():View
		return <div class="groups">{conf.sections.map(s -> <section>
			<h3>{s.title}</h3>
			<ul>{pages.filter(q -> q.section.id == s.id && !q.sub).map(q -> <li><a href={q.url}>{q.title}</a></li>)}</ul>
		</section>)}</div>;

	// where an app runs, and where it ships
	static function platforms():View {
		var where = [
			{name: "macOS", note: "Metal"}, {name: "Windows", note: "Direct3D 11"}, {name: "Linux", note: "OpenGL, Wayland"},
			{name: "iOS", note: "Metal"}, {name: "Android", note: "OpenGL ES"}, {name: "Web", note: "WebGPU, WebGL2"}
		];
		return <figure class="platforms">
			<ul>{where.map(w -> <li><strong>{w.name}</strong><span>{w.note}</span></li>)}</ul>
			<figcaption>One codebase, compiled to native code and WebAssembly. Ships to the App Store, Google Play, notarized macOS and the web.</figcaption>
		</figure>;
	}

	static function reference(to:Null<String>):View {
		if (to == null) throw '${current.file}: <Reference to="ui,view"/>';
		var names = to.split(",").map(s -> s.trim());
		for (n in names)
			if (!FileSystem.exists('src/helder/$n/README.md')) throw '${current.file}: <Reference to="$to"/>: no src/helder/$n/README.md';
		return <p class="reference"><span>Reference</span>{names.map(n -> <a href={repo + '/tree/main/src/helder/$n/README.md'}>{"helder." + n.replace("/", ".")}</a>)}</p>;
	}

	static function visual(src:Null<String>):String {
		if (src == null || !FileSystem.exists(VISUALS + src)) throw '${current.file}: no $VISUALS$src (site/visuals.mjs makes them)';
		return VISUALS + src;
	}

	static function image(attrs:Map<String, String>):View {
		visual(attrs.get("src"));
		var caption = attrs.get("caption");
		return <figure class="visual still">
			<img src={"static/visuals/" + attrs.get("src")} alt={attrs.get("alt") ?? ""} loading="lazy" decoding="async"/>
			{caption == null ? null : <figcaption>{caption}</figcaption>}
		</figure>;
	}

	static function terminal(attrs:Map<String, String>):View {
		var text = File.getContent(visual(attrs.get("src"))).rtrim();
		return <figure class="visual terminal">
			<div class="dots" aria-hidden="true"><i></i><i></i><i></i></div>
			<pre><code>{"$ " + attrs.get("command") + "\n" + text}</code></pre>
		</figure>;
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

	// a page's link: another page (views.md, ../graphics/3d.md#lights) as its
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
		if (e.demo == null) throw '${current.file}: <Example id="$id"/>: it does not run in a browser (no demo header)';
		var region = attrs.get("region");
		var shown = attrs.exists("file") ? e.dir + "/" + attrs.get("file") : e.file;
		if (!FileSystem.exists(shown)) throw '${current.file}: <Example id="$id" file="${attrs.get("file")}"/>: no $shown';
		var codes = [];
		if (region != null) {
			codes.push({lang: shown.endsWith(".hx") ? "haxe" : "ts", title: "", text: source(shown, region)});
			if (e.alt != "" && hasRegion(e.alt, region)) codes.push({lang: "ts", title: "", text: source(e.alt, region)});
		}
		return <div class="example" id={"example-" + e.id}>
			<figure class="visual">
				{stage(e)}
				<figcaption><span>{e.title}</span><span class="live">Live</span><a href={e.source}>Source</a></figcaption>
			</figure>
			{codes.length == 0 ? null : codes.length == 1 ? <div class="code"><div class="name">{label(codes[0].lang)}{copy()}</div><pre data-lang={codes[0].lang}><code>{highlight(codes[0].text, codes[0].lang)}</code></pre></div> : langs(codes)}
		</div>;
	}

	static function hasRegion(file:String, region:String):Bool {
		var text = File.getContent(file);
		for (name in region.split(","))
			if (text.indexOf("// #region " + name.trim()) < 0) return false;
		return true;
	}

	// a file's lines: without its header (the examples' page's title,
	// summary, tags, demo) or the region markers; a region alone when named
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
					else if (from >= 0 && to < 0 && (t == "// #endregion" || t == "// #endregion " + name)) to = k;
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

	// the example's canvas: a WebAssembly island started once it is in view
	// (a sound on a click: browsers play audio only after one), stopped once
	// scrolled out of it (site/stage.js: full screen)
	static function stage(e:Example):View {
		var d = e.demo;
		var sound = d.kind == "sound";
		return <div class={sound ? "stage sound" : "stage"} style={sound ? "" : "--w:" + d.width + "px;--ratio:" + d.width + "/" + d.height}
			data-width={"" + d.width} data-height={"" + d.height} data-one-pixel={d.onePixel ? "" : null}>
			<Island.Wasm src={e.wasm} id={"play-" + e.id} load={sound ? Click : Visible} runner={RUNNER} imports={e.imports} fonts={e.fonts}
				assets={e.assets == "" ? null : e.assets} args={e.args.length > 0 ? e.args : null} stop={Offscreen} canvas={!sound} width={d.width} height={d.height}>
				{e.poster == "" || sound ? null : <img class="poster" src={e.poster} alt="" loading="lazy" decoding="async"/>}
				{sound ? <button class="play" type="button" aria-label={"Play " + e.title}>▶ Play sound</button> : null}
			</Island.Wasm>
			{sound ? null : <button class="full" type="button" aria-label={"Play " + e.title + " full screen"}>Full screen</button>}
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
		// (TSX in a TypeScript sample: its tags highlighted)
		if (language == Ts && text.indexOf("</") >= 0) language = Tsx;
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
