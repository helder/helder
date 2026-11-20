import Docs;
import helder.view.*;
import helder.web.*;
import sys.FileSystem;

using StringTools;

// The landing (<out>/index.html), a screen an idea: what helder is beside a
// live flock (examples/murmuration at fewer birds, started where WebGPU is:
// static/home.js; its picture otherwise), the platforms, six things it
// makes (a picture each from site/visuals, live on a click), a sample in
// both languages, and the way on. Docs.hx writes it after the docs.
typedef Tile = {title:String, pitch:String, href:String, still:String, example:String};

class Home implements Markup {
	static final TILES:Array<Tile> = [
		{title: "Apps and UI", pitch: "Markup and signals, CSS layout, text input and accessibility, drawn on the GPU.", href: "docs/apps/views/",
			still: "mail.webp", example: "mail"},
		{title: "3D", pitch: "glTF models, physically based materials, shadows, post effects and particles.", href: "docs/graphics/3d/",
			still: "lights.webp", example: "scene-lights"},
		{title: "Physics", pitch: "Rigid bodies, joints and a character controller at a fixed step.", href: "docs/games/physics/",
			still: "falling.webp", example: "falling"},
		{title: "2D and canvas", pitch: "Paths, gradients, images and sprites, on the GPU or in a page.", href: "docs/graphics/2d/",
			still: "canvas.webp", example: ""},
		{title: "Web pages", pitch: "Static pages with live islands: a helder program inside your page.", href: "docs/web/pages/",
			still: "palette.webp", example: "ts-palette"},
		{title: "Device services", pitch: "Settings, locale and formatting, links and storage, one API on every platform.", href: "docs/apps/services/",
			still: "services.webp", example: "services"}
	];
	static final TS = 'import { signal } from "helder/view";
import { UiWindow, Surface } from "helder/ui";

const count = signal(0);

UiWindow.run(
  <Surface title="Counter" width={320} height={200}>
    <view grow={1} align-items="center" justify="center" row-gap={12}>
      <text font-size={32}>{count}</text>
      <view:button padding="8 16" onPress={() => count(c => c + 1)}>
        +1
      </view:button>
    </view>
  </Surface>
);';
	static final HAXE = 'import helder.view.*;
import helder.view.graph.Graph.*;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;

class Counter implements Markup {
  static function main() {
    var count = signal(0);
    UiWindow.run(<Surface title="Counter" width={320} height={200}>
      <view grow={1} align-items="center" justify="center" row-gap={12}>
        <text font-size={32}>{count}</text>
        <view:button padding="8 16" onPress={() -> count(c -> c + 1)}>
          +1
        </view:button>
      </view>
    </Surface>);
  }
}';

	public static function write(out:String, theme:Theme, examples:Map<String, Example>, repo:String) {
		for (t in TILES)
			if (!FileSystem.exists("site/visuals/" + t.still)) throw 'site/docs/Home.hx: no site/visuals/${t.still} (site/visuals.mjs)';
		var flock = examples.get("murmuration");
		Static.write(out + "/index.html", Static.document(<html lang="en">
			<head>
				<meta charset="utf-8"/>
				<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/>
				<base href="./"/>
				<title>{theme.brand + ": apps and games for every screen"}</title>
				<meta name="description" content="Build apps and games in TypeScript or Haxe, compiled to native code for desktop and phones and to WebAssembly for the web."/>
				<link rel="stylesheet" href="static/site.css"/>
				{theme.css.map(h -> <link rel="stylesheet" href={h}/>)}
				<script src="static/docs.js" defer></script>
				<script src="static/stage.js" defer></script>
				<script src="static/loader.js" defer></script>
				<script src="static/home.js" defer></script>
				{theme.js.map(h -> <script src={h} defer></script>)}
			</head>
			<body class="home">
				{theme.notice == "" ? null : <div class="notice">{theme.notice}</div>}
				<header class="top"><div class="wrap">
					<a class="brand" href={theme.home}>{theme.brand}</a>
					<nav aria-label="Site">{theme.nav.map(l -> <a href={l.href}>{l.label}</a>)}</nav>
					{theme.action.label == "" ? null : <a class="btn" href={theme.action.href}>{theme.action.label}</a>}
				</div></header>
				<main>
					<section class="hero wrap">
						<h1>Apps and games for every screen, from one codebase.</h1>
						<p class="lede">helder compiles TypeScript or Haxe to native code for desktop and phones, and to WebAssembly for the web. One renderer, one UI, drawn on the GPU.</p>
						<div class="acts">
							<a class="btn primary" href="docs/start/install/">Get started</a>
							<div class="install"><code id="install">npm install helder@next</code><button type="button" class="copy-line" data-copy="install" aria-label="Copy the install command" hidden="">Copy</button></div>
						</div>
						{flock == null || flock.demo == null ? null : <figure class="hero-stage">
							{flight(flock)}
							<figcaption>Half a million starlings, steered on your GPU. Drag to turn. <a href={flock.source}>Source</a></figcaption>
						</figure>}
					</section>
					<section class="band wrap" aria-labelledby="everywhere">
						<h2 id="everywhere">One codebase, every platform.</h2>
						<p class="say">The same program builds for six systems and ships to their stores. No Xcode or Android SDK needed to build.</p>
						{platforms()}
					</section>
					<section class="band wrap" aria-labelledby="makes">
						<h2 id="makes">What you can make.</h2>
						<p class="say">Each one runs here, in your browser. Press to play it.</p>
						<div class="tiles">{TILES.map(t -> tile(t, examples))}</div>
					</section>
					<section class="band wrap sample" aria-labelledby="write">
						<div>
							<h2 id="write">Write it your way.</h2>
							<p class="say">Signals hold state, markup reads them, and only what changed is redrawn. The same app in TypeScript or Haxe.</p>
							<p><a class="go" href="docs/start/typescript/">TypeScript or Haxe →</a></p>
						</div>
						{Docs.langs([{lang: "tsx", title: "", text: TS}, {lang: "haxe", title: "", text: HAXE}])}
					</section>
				</main>
				<footer class="foot"><div class="wrap">
					<span class="brand">{theme.brand}</span>
					<a href="docs/">Docs</a><a href="examples/">Examples</a><a href={repo}>GitHub</a>
					{theme.footer.map(l -> <a href={l.href}>{l.label}</a>)}
				</div></footer>
			</body>
		</html>));
	}

	// the flock: on a click (static/home.js clicks it where WebGPU is), fewer birds than the example's whole
	static function flight(e:Example):View {
		var d = e.demo;
		return <div class="stage" style={"--w:" + d.width + "px;--ratio:16/9"} data-width={"" + d.width} data-height={"" + d.height}>
			<Island.Wasm src={e.wasm} id="play-murmuration" load={Click} runner="static/helder/os/browser.mjs" imports={e.imports} fonts={e.fonts}
				assets={e.assets == "" ? null : e.assets} args={["--birds", "65536"]} stop={Offscreen} width={d.width} height={d.height}>
				{e.poster == "" ? null : <img class="poster" src={e.poster} alt="Starlings wheeling over a marsh at dusk" fetchpriority="high"/>}
				<button class="play" type="button" aria-label="Play Murmuration">▶ Play</button>
			</Island.Wasm>
			<button class="full" type="button" aria-label="Murmuration full screen">Full screen</button>
			<button class="exit" type="button" aria-label="Leave full screen">✕</button>
		</div>;
	}

	static function tile(t:Tile, examples:Map<String, Example>):View {
		var e = t.example == "" ? null : examples.get(t.example);
		if (t.example != "" && (e == null || e.demo == null)) throw 'site/docs/Home.hx: ${t.example} is no example that runs in a browser';
		var still = "static/visuals/" + t.still;
		return <article class="tile">
			{e == null ? <a class="shot" href={t.href}><img src={still} alt="" loading="lazy" decoding="async"/></a> : <div class="stage shot"
				style={"--w:" + e.demo.width + "px;--ratio:" + e.demo.width + "/" + e.demo.height} data-width={"" + e.demo.width} data-height={"" + e.demo.height}>
				<Island.Wasm src={e.wasm} id={"play-" + e.id} load={Click} runner="static/helder/os/browser.mjs" imports={e.imports} fonts={e.fonts}
					assets={e.assets == "" ? null : e.assets} stop={Offscreen} width={e.demo.width} height={e.demo.height}>
					<img class="poster" src={still} alt="" loading="lazy" decoding="async"/>
					<button class="play" type="button" aria-label={"Play " + t.title}>▶</button>
				</Island.Wasm>
			</div>}
			<h3><a href={t.href}>{t.title} <span aria-hidden="true">→</span></a></h3>
			<p>{t.pitch}</p>
		</article>;
	}

	static function platforms():View {
		var all = [
			{name: "macOS", kind: "desktop", ships: "Notarized"}, {name: "Windows", kind: "desktop", ships: "The .exe"},
			{name: "Linux", kind: "desktop", ships: "tar.gz, Flatpak"}, {name: "iOS", kind: "phone", ships: "TestFlight, App Store"},
			{name: "Android", kind: "phone", ships: "Google Play"}, {name: "Web", kind: "web", ships: "Any host, helder.run"}
		];
		return <ul class="platforms">{all.map(p -> <li>
			<span class={"glyph " + p.kind} aria-hidden="true"></span>
			<strong>{p.name}</strong>
			<span>{p.ships}</span>
		</li>)}</ul>;
	}
}
