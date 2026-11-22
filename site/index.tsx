// The examples' pages: examples/index.html, every example of examples/ a
// card of its title, summary and tags (its header), those that run in a
// browser with a Play button starting their wasm32 build in the page; and
// examples/<id>/index.html for each with a page.json: its demo,
// description, numbers (site/numbers.mjs's, measured headless, read from
// examples/numbers.json by numbers.js; real devices' from page.json;
// three.js' for the same scene) and credits. TSX through helder's
// TypeScript frontend, rendered to HTML by helder.web's static renderer
// when this program runs (site/build.mjs builds it after the examples and
// writes the JSON it imports: their headers and builds, and the site's
// theme: its top bar's links, a host's sheets and starters).
import { Static, Island } from "helder/web";
import site from "../bin/site-build/examples.json";

interface Demo {
	// canvas (width x height) or sound (no canvas)
	kind: string;
	width: number;
	height: number;
	// a pixel a point, not multisampled (`canvas WxH 1x`: stage.js's run options)
	onePixel: boolean;
}

// an Android build of it, for phones: the file, its size, the commit it was built from
interface Apk {
	file: string;
	bytes: number;
	commit: string;
}

// a row of the numbers: on a real device (page.json's), or a slot filled from numbers.json
interface Device {
	device: string;
	firstFrameMs: string;
	// (all the Play button fetches: the module too, gzipped; "–" when not measured)
	fetchedGzMB: string;
	downloadMB: string;
	memoryMB: string;
	p50Ms: string;
	p99Ms: string;
}

// the same scene elsewhere (three.js' example): what it downloads
interface Compare {
	what: string;
	url: string;
	downloadMB: string;
	note: string;
}

interface Page {
	description: string[];
	compare: Compare[];
	devices: Device[];
	credits: string[];
	// what numbers.mjs plays: the program's args beyond the data folder (a scene each, by label)
	numbers: string[];
	// how long numbers.mjs plays it (0: its default)
	seconds: number;
}

interface Example {
	id: string;
	title: string;
	summary: string;
	tags: string[];
	source: string;
	demo: Demo | null;
	poster: string;
	// (its build: the module, the browser modules it imports, fonts, its assets' list; "" and [] without a demo)
	wasm: string;
	imports: string[];
	fonts: string[];
	assets: string;
	apk: Apk | null;
	// the program's arguments (a data folder's URL), its page (null: none), its data's bytes
	args: string[];
	page: Page | null;
	dataBytes: number;
	// docs/examples' (the docs' own: played in their pages, not listed here)
	docs: boolean;
}

// a video site/reel.mjs records (examples/media/<id>.mp4 and its poster): the showreel, then a clip of each showcase demo
interface Clip {
	id: string;
	// the example it shows (its card's id)
	example: string;
	title: string;
	summary: string;
	video: string;
	poster: string;
	seconds: number;
}

// the site's theme (site/build.mjs: its defaults, or a host's SITE_THEME); links relative to the site's root
interface Link {
	// (examples, docs: the part of the site it marks current)
	id: string;
	label: string;
	href: string;
}

interface Starter {
	title: string;
	summary: string;
	href: string;
	image: string;
	width: number;
	height: number;
	kind: string;
}

interface Theme {
	brand: string;
	home: string;
	nav: Link[];
	// a button at the top bar's end ("" label: none)
	action: Link;
	css: string[];
	js: string[];
	notice: string;
	footer: Link[];
	// cards above the examples (a host's: helder.build's projects to open in its studio); none without items
	starters: { title: string; lede: string; items: Starter[] };
}

const theme = site.theme as Theme;
const examples = (site.examples as Example[]).filter(e => !e.docs);
const clips = site.clips as Clip[];
const playable = examples.filter(e => e.demo !== null);
const others = examples.filter(e => e.demo === null);
const featured = playable.filter(e => e.id === "hadal" && e.wasm !== "");
const catalog = playable.filter(e => !featured.includes(e));
const topic = (e: Example) => e.page !== null ? "measure" : e.tags.indexOf("ui") >= 0 ? "interface" : "render";
const RUNNER = "static/helder/os/browser.mjs";
const pageOf = (e: Example) => "examples/" + e.id + "/";

// the page's head: the site's sheet and scripts, a host's after them; base: the site's root from the page
function Head(props: { title: string, about: string, base: string, numbers: boolean }) {
	return <head>
		<meta charset="utf-8" />
		<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
		<base href={props.base} />
		<title>{props.title}</title>
		<meta name="description" content={props.about} />
		<link rel="stylesheet" href="static/site.css" />
		{theme.css.map(h => <link rel="stylesheet" href={h} />)}
		<script src="static/stage.js" defer></script>
		<script src="static/loader.js" defer></script>
		{props.numbers ? <script src="static/numbers.js" defer></script> : null}
		{theme.js.map(h => <script src={h} defer></script>)}
	</head>;
}

// the top bar: the brand, the site's links (the current one marked), a host's button
function Top(props: { current: string }) {
	return <header class="top"><div class="wrap">
		<a class="brand" href={theme.home}>{theme.brand}</a>
		<nav aria-label="Site">{theme.nav.map(l => <a href={l.href} aria-current={l.id !== "" && l.id === props.current ? "page" : undefined}>{l.label}</a>)}</nav>
		{theme.action.label !== "" ? <a class="btn" href={theme.action.href}>{theme.action.label}</a> : null}
	</div></header>;
}

function Foot() {
	return <footer class="foot"><div class="wrap">
		{theme.footer.length > 0 ? theme.footer.map(l => <a href={l.href}>{l.label}</a>)
			: <span>Rendered by helder.web's static renderer from site/index.tsx and the docs' Markdown.</span>}
	</div></footer>;
}

// the canvas (or, for a sound, none) its Play button starts: a WebAssembly island loaded on the first click
function Stage(props: { ex: Example, showcase?: boolean }) {
	const ex = props.ex;
	const demo = ex.demo as Demo;
	const sound = demo.kind === "sound";
	const recordings = clips.filter(c => c.example === ex.id);
	const still = ex.poster !== "" ? ex.poster : recordings.length > 0 ? recordings[0].poster : "";
	const poster = still !== "" ? ";--stage-poster:url('/" + still + "')" : "";
	const style = sound ? "" : "--w:" + demo.width + "px;--ratio:" + demo.width + "/" + demo.height + poster;
	const game = ex.tags.indexOf("game") >= 0;
	return <div class={props.showcase ? "stage showcase-stage" : sound ? "stage sound" : "stage"} style={style} data-width={"" + demo.width} data-height={"" + demo.height} data-game={game ? "" : undefined} data-one-pixel={demo.onePixel ? "" : undefined}>
		<Island.Wasm src={ex.wasm} id={"play-" + ex.id} load="click" runner={RUNNER} imports={ex.imports} fonts={ex.fonts} assets={ex.assets === "" ? undefined : ex.assets}
			args={ex.args.length > 0 ? ex.args : undefined} stop={ex.args.length > 0 ? "offscreen" : undefined}
			canvas={!sound} width={demo.width} height={demo.height}>
			<button class="play" type="button" aria-label={(props.showcase ? "Launch " : "Play ") + ex.title}>{props.showcase ? "Launch " + ex.title + " ↗" : sound ? "▶ Play sound" : "▶ Play"}</button>
			<span class="size">{demo.width + "×" + demo.height}</span>
		</Island.Wasm>
		{sound ? null : <button class="full" type="button" aria-label={"Play " + ex.title + " full screen"}>⛶ Full screen</button>}
		{sound ? null : <button class="exit" type="button" aria-label="Leave full screen">✕</button>}
	</div>;
}

// its Android build's link, size and commit
function Download(props: { apk: Apk }) {
	const a = props.apk;
	const mb = Math.round(a.bytes / 104857.6) / 10;
	return <p class="apk"><a href={a.file} download="">Download for Android (APK)</a>{" · " + mb + " MB, built from " + a.commit}</p>;
}

function Card(props: { ex: Example }) {
	const ex = props.ex;
	return <article class="card" id={ex.id}>
		{ex.demo !== null ? <Stage ex={ex} /> : null}
		<div class="card-copy">
			<div class="row"><h3>{ex.title}</h3><ul class="tags">{ex.tags.map(t => <li>{t}</li>)}</ul></div>
			<p>{ex.summary}</p>
			{ex.apk !== null ? <Download apk={ex.apk as Apk} /> : null}
			<p class="links">{ex.page !== null ? <a href={pageOf(ex)}>Read the measurements</a> : null}<a href={ex.source}>Read source</a></p>
			{clips.filter(c => c.example === ex.id).map(c => <details class="recording"><summary>Watch recording · {Math.round(c.seconds)}s</summary><Video c={c} /></details>)}
		</div>
	</article>;
}

// the numbers' row of a device (a real one's, from page.json; CI's: slots numbers.js fills)
function Row(props: { d: Device, slot: string }) {
	const d = props.d;
	const cell = (key: string, value: string) => props.slot === "" ? <td>{value}</td> : <td data-num={props.slot + "." + key}>{value}</td>;
	return <tr>
		<th scope="row">{d.device}</th>
		{cell("firstFrameMs", d.firstFrameMs)}
		{cell("fetchedGzMB", d.fetchedGzMB)}
		{cell("downloadMB", d.downloadMB)}
		{cell("memoryMB", d.memoryMB)}
		{cell("p50Ms", d.p50Ms)}
		{cell("p99Ms", d.p99Ms)}
	</tr>;
}

function Numbers(props: { ex: Example }) {
	const ex = props.ex;
	const page = ex.page as Page;
	const scenes = page.numbers.length > 0 ? page.numbers : [""];
	const ci = (label: string): Device => ({ device: "CI: headless Chromium, SwiftShader (software)" + (label === "" ? "" : ", " + label), firstFrameMs: "…", fetchedGzMB: "…",
		downloadMB: "…", memoryMB: "…", p50Ms: "…", p99Ms: "…" });
	return <table class="numbers">
		<thead><tr><th scope="col"></th><th scope="col">First frame (ms)</th><th scope="col">Fetched, gzipped (MB)</th><th scope="col">Data download (MB)</th><th scope="col">GPU textures (MB)</th>
			<th scope="col">Frame p50 (ms)</th><th scope="col">Frame p99 (ms)</th></tr></thead>
		<tbody>
			{scenes.map(label => <Row d={ci(label)} slot={ex.id + (label === "" ? "" : "." + label)} />)}
			{page.devices.map(d => <Row d={d} slot="" />)}
		</tbody>
	</table>;
}

function DemoPage(props: { ex: Example }) {
	const ex = props.ex;
	const page = ex.page as Page;
	return <html lang="en">
		<Head title={ex.title + " · Examples · " + theme.brand} about={ex.summary} base="../../" numbers={true} />
		<body>
			{theme.notice !== "" ? <div class="notice">{theme.notice}</div> : null}
			<Top current="examples" />
			<main class="wrap"><article class="page" id={ex.id}>
				<div class="intro">
					<a class="back" href="examples/">← Examples</a>
					<h1>{ex.title}</h1>
					<p class="lede">{ex.summary}</p>
					{ex.demo !== null ? <Stage ex={ex} /> : null}
				</div>
				{page.description.map(p => <p>{p}</p>)}
				<h2>Numbers</h2>
				<p>The first frame: from the program's start to its first frame (a model's fetch, decoding and upload included); fetched: all the Play
					button downloads, the module, its browser modules, fonts and assets, gzipped; the data download: what the program fetches
					beyond the module{ex.dataBytes > 0 ? " (" + Math.round(ex.dataBytes / 104857.6) / 10 + " MB of data beside it)" : ""}; GPU textures:
					the bytes of the textures alive (helder.gfx's Device.textureBytes); frame times from its overlay. CI's are headless software
					rendering, not a phone's or a desktop's GPU; the real devices' rows are measured by hand.</p>
				<Numbers ex={ex} />
				{page.compare.length > 0 ? <h2>The same elsewhere</h2> : null}
				{page.compare.length > 0 ? <ul>{page.compare.map(c => <li><a href={c.url}>{c.what}</a>{": " + c.downloadMB + " MB downloaded. " + c.note}</li>)}</ul> : null}
				<h2>Credits</h2>
				<ul>{page.credits.map(c => <li>{c}</li>)}</ul>
				<ul class="tags">{ex.tags.map(t => <li>{t}</li>)}</ul>
				<p class="links"><a href={ex.source}>Read source</a></p>
			</article></main>
			<Foot />
		</body>
	</html>;
}

function Video(props: { c: Clip }) {
	const c = props.c;
	return <div class="video"><video data-clip={c.id} src={c.video} poster={c.poster} controls muted loop playsinline preload="none" aria-label={c.title}></video></div>;
}

for (const ex of examples) {
	if (ex.page !== null) Static.write(site.dir + "/" + pageOf(ex) + "index.html", Static.document(<DemoPage ex={ex} />));
}

const topics = [
	{ id: "interface", title: "Interfaces and interaction", guide: "Build an interface", href: "docs/apps/views/" },
	{ id: "measure", title: "Graphics and performance", guide: "Explore 3D scenes", href: "docs/graphics/3d/" },
	{ id: "render", title: "Rendering, physics and sound", guide: "Add physics", href: "docs/games/physics/" }
];
const starters = theme.starters;
Static.write(site.dir + "/examples/index.html", Static.document(<html lang="en">
	<Head title={"Examples · " + theme.brand} about="helder's examples: apps and games in TypeScript and Haxe, compiled to native code and WebAssembly, playing in your browser." base="../" numbers={false} />
	<body class="examples-page">
		{theme.notice !== "" ? <div class="notice">{theme.notice}</div> : null}
		<Top current="examples" />
		<main class="wrap">
			<section class="intro examples-intro">
				<h1>Examples</h1>
				<p class="lede">Explore an app built in Helder, run a graphics demo, or open a project to make your own.</p>
				<nav class="example-jumps" aria-label="Browse examples">
					{starters.items.length > 0 ? <a class="btn" href="examples/#studio-examples">Open in Studio</a> : null}
					<a class="btn" href="examples/#browser-demos">Run demos</a>
					<a class="btn" href="examples/#native-examples">Browse native examples</a>
				</nav>
			</section>
			{featured.map(ex => <section class="band showcase" aria-labelledby="showcase-title">
				<h2 class="eyebrow" id="showcase-title">Featured showcase</h2>
				<article class="card" id={ex.id}>
					<div class="showcase-copy">
						<div><h3>{ex.title}</h3><p>{ex.summary}</p></div>
						<a class="btn" href={ex.source}>Read source ↗</a>
					</div>
					<Stage ex={ex} showcase={true} />
				</article>
			</section>)}
			{starters.items.length > 0 ? <section class="band starters" aria-label={starters.title} id="studio-examples">
				<h2>{starters.title}</h2>
				{starters.lede !== "" ? <p>{starters.lede}</p> : null}
				<div class="grid">{starters.items.map(s => <a class="card" href={s.href}>
					<div class="cover">{s.image !== "" ? <img src={s.image} width={"" + s.width} height={"" + s.height} alt="" loading="lazy" decoding="async" /> : <span class="plus" aria-hidden="true"></span>}</div>
					<div class="row"><h3>{s.title}</h3>{s.kind !== "" ? <span class="kind">{s.kind}</span> : null}</div>
					<p>{s.summary}</p><span class="starter-action">Open in Studio →</span>
				</a>)}</div>
			</section> : null}
			<section class="band" aria-label="Play in your browser" id="browser-demos">
				<h2>Play in your browser</h2>
				<nav class="example-jumps" aria-label="Demo topics">{topics.map(t => <a class="btn" href={"examples/#" + t.id}>{t.title}</a>)}</nav>
				{topics.map(t => <section class="demo-topic" id={t.id}>
					<h2>{t.title}</h2>
					<a class="guide-link" href={t.href}>{t.guide} →</a>
					<div class="grid">{catalog.filter(ex => topic(ex) === t.id).map(ex => <Card ex={ex} />)}</div>
				</section>)}
			</section>
			<section class="band" aria-label="Native examples" id="native-examples">
				<h2>Native examples</h2>
				<p>From a Helder checkout, run <code>helder run</code> with the example’s folder or entry file.</p>
				<div class="grid">{others.map(ex => <Card ex={ex} />)}</div>
			</section>
		</main>
		<Foot />
	</body>
</html>));
