// The long pages the document benches and checks read: fetched once into
// bin/bench/html with their <link rel=stylesheet>s, and a sheets.json of
// URL to file, as the engine resolves them (its "#page": the page's URL).
//
//   node tests/bench/pages.mjs      fetches the HTML Standard, the ECMAScript spec, three Wikipedia
//                                   articles, War and Peace and WebKit's chapter-reflow
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = 'bin/bench/html';

async function fetchTo(url, file) {
	if (fs.existsSync(file)) return;
	const res = await fetch(url, { headers: { 'user-agent': 'helder-bench' } });
	if (!res.ok) throw new Error(`${url}: ${res.status}`);
	fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
}

// (a page and its sheets: {name, url, file, sheets: the sheets.json's path})
export async function page(name, url, fix) {
	fs.mkdirSync(dir, { recursive: true });
	const file = `${dir}/${name}.html`;
	if (!fs.existsSync(file) && fix) {
		await fetchTo(url, file);
		fs.writeFileSync(file, fix(fs.readFileSync(file, 'utf8')));
	}
	await fetchTo(url, file);
	const sheets = {};
	const html = fs.readFileSync(file, 'utf8');
	let k = 0;
	for (const m of html.matchAll(/<link\b[^>]*>/g)) {
		const tag = m[0];
		if (!/rel="?stylesheet"?/.test(tag)) continue;
		// (quoted or not: ecmarkup writes href=assets/css/ecmarkup.css)
		const m2 = /href=(?:"([^"]+)"|'([^']+)'|([^\s>]+))/.exec(tag);
		const href = (m2?.[1] ?? m2?.[2] ?? m2?.[3])?.replaceAll('&amp;', '&');
		if (!href) continue;
		const abs = new URL(href, url).href;
		const f = `${dir}/${name}-sheet-${k++}.css`;
		await fetchTo(abs, f);
		sheets[abs] = f;
		// (the plain join too: the engine resolves without percent-encoding)
		if (href.startsWith('/')) sheets[new URL(url).origin + href] = f;
	}
	// (and the page's own URL, what its relative links resolve against: not every page names it, rel=canonical)
	sheets['#page'] = url;
	fs.writeFileSync(`${dir}/${name}-sheets.json`, JSON.stringify(sheets, null, 2));
	return { name, url, file, sheets: `${dir}/${name}-sheets.json` };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	await page('html-spec', 'https://html.spec.whatwg.org/');
	await page('wikipedia', 'https://en.wikipedia.org/wiki/World_War_II');
	// (Wikipedia's longest: tables of some 2,700 rows, its page's background far past a layer's 8192 pixels)
	await page('telemann', 'https://en.wikipedia.org/wiki/List_of_vocal_works_by_Georg_Philipp_Telemann');
	// (the ECMAScript specification on one page; a novel, Gutenberg's War and Peace; WebKit's chapter-reflow,
	// its column shown; Wikipedia's prose: Japanese pitch accent)
	await page('ecma262', 'https://tc39.es/ecma262/');
	// (gutenberg.org answers automated fetches 503: PGLAF's mirror of it)
	await page('war-and-peace', 'https://gutenberg.pglaf.org/2/6/0/2600/2600-h/2600-h.htm');
	// (its column shown, as the test shows it while it reflows it: no runner, no script)
	await page('chapter-reflow', 'https://raw.githubusercontent.com/WebKit/WebKit/main/PerformanceTests/Layout/chapter-reflow.html', html =>
		html.replace(/<script[\s\S]*?<\/script>/g, '').replace('style="width: 300px; display: none;"', 'style="width: 300px"'));
	await page('pitch-accent', 'https://en.wikipedia.org/wiki/Japanese_pitch_accent');
}
