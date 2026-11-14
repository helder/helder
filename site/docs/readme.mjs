// The packages' READMEs from the docs: docs/ is the source, each section's
// `readmes` in docs/docs.json a README written from its pages, in order,
// so that a package's README on GitHub (or in an editor, or to an agent
// reading the repository) says what its pages say. The first page's title
// is the README's (or the readme's `title`), the others' its sections
// (their headings a level down); an <Example id="..."/> a link to its
// file and how to run it; a link to another page an anchor in the same
// README, or the page itself when it is in another.
//
//   node site/docs/readme.mjs            write them
//   node site/docs/readme.mjs --check    fail if one is not what the pages make (tests' examples lane)
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
process.chdir(root);
const check = process.argv.includes('--check');
const conf = JSON.parse(fs.readFileSync('docs/docs.json', 'utf8'));
const HEADER = /^\/\/ *(title|summary|tags|demo|apk|data): *(.*)$/;

// GitHub's heading ids (Markdown.hx's slug)
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9_\- ]/g, '').replace(/ /g, '-');
const plain = (s) => s.replace(/`/g, '').replace(/\*\*?|__?/g, '').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');

function header(file) {
	const head = {};
	for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
		if (!line.startsWith('//')) break;
		const m = HEADER.exec(line.trim());
		if (m) head[m[1]] = m[2].trim();
	}
	return head.title ? head : null;
}

// an example by its id: examples/<id> or docs/examples/<id>, its entry (its Haxe program, else main.ts)
function example(id) {
	for (const dir of [`examples/${id}`, `docs/examples/${id}`]) {
		if (!fs.existsSync(dir)) continue;
		const files = fs.readdirSync(dir).sort();
		const entry = files.find((f) => f.endsWith('.hx') && header(`${dir}/${f}`)) ?? files.find((f) => /^main\.tsx?$/.test(f) && header(`${dir}/${f}`));
		if (entry) return { dir, entry: `${dir}/${entry}`, title: header(`${dir}/${entry}`).title };
	}
	throw new Error(`site/docs/readme.mjs: <Example id="${id}"/>: no such example`);
}

function page(section, id) {
	const file = `docs/${section.id}/${id}.md`;
	const text = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
	const m = /^# (.*)\n/.exec(text);
	if (!m) throw new Error(`${file}: a page starts with its title (# Title)`);
	return { id, file, title: m[1].trim(), body: text.slice(m[0].length) };
}

function readme(section, spec) {
	const pages = spec.pages.map((id) => page(section, id));
	const here = new Map(pages.map((p) => [`${p.id}.md`, p]));
	const out = [`<!-- Generated from ${pages.map((p) => p.file).join(', ')} by site/docs/readme.mjs: edit those, not this file. -->`, ''];
	pages.forEach((p, k) => {
		const first = k === 0;
		out.push(first ? `# ${spec.title ?? p.title}` : `## ${p.title}`);
		let fence = null;
		for (const line of p.body.split('\n')) {
			const f = /^\s*(```+|~~~+)/.exec(line);
			if (f && (!fence || line.trim().startsWith(fence))) {
				fence = fence ? null : f[1];
				out.push(line);
				continue;
			}
			if (fence) {
				out.push(line);
				continue;
			}
			const h = /^(#{2,5}) (.*)$/.exec(line);
			if (h && !first) {
				out.push(`#${h[1]} ${h[2]}`);
				continue;
			}
			const c = /^<Example ((?:\s*[a-z]+="[^"]*")*)\s*\/>\s*$/.exec(line.trim());
			if (c) {
				const attrs = Object.fromEntries([...c[1].matchAll(/([a-z]+)="([^"]*)"/g)].map((a) => [a[1], a[2]]));
				const e = example(attrs.id);
				const file = attrs.file ? `${e.dir}/${attrs.file}` : e.entry;
				out.push(`Example: [${e.title}](/${file}) (\`helder run ${e.entry}\`; it plays in the docs' page).`);
				continue;
			}
			out.push(line.replace(/\]\(([^)#\s]+\.md)(#[^)]*)?\)/g, (all, target, anchor) => {
				if (target.startsWith('/') || /^[a-z]+:/.test(target)) return all;
				const p2 = here.get(target);
				if (p2) return `](${anchor ?? '#' + slug(plain(p2 === pages[0] ? spec.title ?? p2.title : p2.title))})`;
				return `](/docs/${section.id}/${target}${anchor ?? ''})`;
			}));
		}
	});
	return out.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n';
}

let stale = 0;
for (const section of conf.sections)
	for (const spec of section.readmes ?? []) {
		const text = readme(section, spec);
		const was = fs.existsSync(spec.path) ? fs.readFileSync(spec.path, 'utf8').replace(/\r\n/g, '\n') : '';
		if (was === text) continue;
		if (check) {
			console.error(`${spec.path} is not what docs/${section.id}/ makes: node site/docs/readme.mjs (edit the pages, not the README)`);
			stale++;
		} else {
			fs.writeFileSync(spec.path, text);
			console.log(`wrote ${spec.path}`);
		}
	}
if (stale) process.exit(1);
