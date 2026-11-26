// Real stylesheets for helder.css's bench and differential check, fetched
// once into bin/css/sheets (not committed), each at a pinned version from
// npm (jsdelivr): frameworks' builds, Tailwind's full output, GitHub's
// Primer. Prints the paths; `node tests/css/sheets.mjs` alone fetches.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const DIR = path.join(here, '../../bin/css/sheets');

export const SHEETS = {
	'bootstrap.css': 'bootstrap@5.3.3/dist/css/bootstrap.css',
	'tailwind.css': 'tailwindcss@2.2.19/dist/tailwind.css',
	'bulma.css': 'bulma@1.0.2/css/bulma.css',
	'primer.css': '@primer/css@21.5.1/dist/primer.css',
	'foundation.css': 'foundation-sites@6.8.1/dist/css/foundation.css',
	'fontawesome.css': '@fortawesome/fontawesome-free@6.6.0/css/all.css',
	'animate.css': 'animate.css@4.1.1/animate.css',
	'normalize.css': 'normalize.css@8.0.1/normalize.css',
};

export async function fetchSheets() {
	fs.mkdirSync(DIR, { recursive: true });
	const out = [];
	for (const [name, pkg] of Object.entries(SHEETS)) {
		const file = path.join(DIR, name);
		if (!fs.existsSync(file)) {
			const r = await fetch(`https://cdn.jsdelivr.net/npm/${pkg}`);
			if (!r.ok) throw new Error(`${pkg}: ${r.status}`);
			fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
		}
		out.push(file);
	}
	return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url))
	for (const f of await fetchSheets()) console.log(`${f} ${Math.round(fs.statSync(f).size / 1024)} KB`);
