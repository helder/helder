// The long pages the document benches and checks read: fetched once into
// bin/bench/html with their <link rel=stylesheet>s, and a sheets.json of
// URL to file, as the engine resolves them.
//
//   node tests/bench/pages.mjs      fetches the HTML Standard and a Wikipedia article
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
export async function page(name, url) {
	fs.mkdirSync(dir, { recursive: true });
	const file = `${dir}/${name}.html`;
	await fetchTo(url, file);
	const sheets = {};
	const html = fs.readFileSync(file, 'utf8');
	let k = 0;
	for (const m of html.matchAll(/<link\b[^>]*>/g)) {
		const tag = m[0];
		if (!/rel="?stylesheet"?/.test(tag)) continue;
		const href = /href="([^"]+)"/.exec(tag)?.[1]?.replaceAll('&amp;', '&');
		if (!href) continue;
		const abs = new URL(href, url).href;
		const f = `${dir}/${name}-sheet-${k++}.css`;
		await fetchTo(abs, f);
		sheets[abs] = f;
		// (the plain join too: the engine resolves without percent-encoding)
		if (href.startsWith('/')) sheets[new URL(url).origin + href] = f;
	}
	fs.writeFileSync(`${dir}/${name}-sheets.json`, JSON.stringify(sheets, null, 2));
	return { name, url, file, sheets: `${dir}/${name}-sheets.json` };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	await page('html-spec', 'https://html.spec.whatwg.org/');
	await page('wikipedia', 'https://en.wikipedia.org/wiki/World_War_II');
}
