// The pdf lane's written files (tests/pdf/WriteCheck.hx: bin/pdf/written) read
// by pdf.js in node (pdfjs-dist's legacy build, no browser): each page's
// text (getTextContent, a newline at each end of line) against what was
// drawn, the document's links (getAnnotations), named destinations, outline
// and information; then `qpdf --check` on each where qpdf is installed.
// Without pdfjs-dist (PDFJS=<its directory>, else node_modules/pdfjs-dist)
// it says so and passes.
//
//   node tests/pdf/written.mjs bin/pdf/written
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";

const dir = process.argv[2] ?? "bin/pdf/written";
const expected = JSON.parse(readFileSync(path.join(dir, "expected.json"), "utf8"));
let failed = 0;
const fail = m => { failed++; console.log(`written: ${m}`); };

const dist = process.env.PDFJS ?? "node_modules/pdfjs-dist";
const build = path.resolve(dist, "legacy/build/pdf.mjs");
if (!existsSync(build)) console.log(`written: pdf.js not found (${dist}): its checks skipped`);
else {
	const pdfjs = await import(pathToFileURL(build).href);
	for (const [name, want] of Object.entries(expected)) {
		const data = new Uint8Array(readFileSync(path.join(dir, name + ".pdf")));
		const task = pdfjs.getDocument({ data, verbosity: 0, isEvalSupported: false });
		const doc = await task.promise;
		const page = await doc.getPage(1);
		const tc = await page.getTextContent();
		const text = tc.items.map(t => t.str + (t.hasEOL ? "\n" : "")).join("").trim();
		if (text !== want.text) fail(`${name}.pdf: pdf.js reads ${JSON.stringify(text)}, drawn ${JSON.stringify(want.text)}`);
		if (want.links) {
			const links = (await page.getAnnotations()).filter(a => a.subtype === "Link").map(a => a.url ? { url: a.url } : { dest: a.dest });
			if (JSON.stringify(links) !== JSON.stringify(want.links)) fail(`${name}.pdf: links ${JSON.stringify(links)}`);
			// (each anchor by its name: a page and a place)
			for (const d of want.destinations) {
				const dest = await doc.getDestination(d);
				if (!Array.isArray(dest) || dest[1]?.name !== "XYZ") fail(`${name}.pdf: the destination ${d} ${JSON.stringify(dest)}`);
			}
			const shape = list => JSON.stringify(list.map(o => ({ title: o.title, items: o.items.map(i => typeof i === "string" ? i : i.title) })));
			const outline = shape(await doc.getOutline() ?? []);
			if (outline !== shape(want.outline)) fail(`${name}.pdf: outline ${outline}`);
			const meta = await doc.getMetadata();
			if (meta.info.Title !== want.title || meta.info.Author !== want.author || meta.info.Language !== want.language) fail(`${name}.pdf: information ${JSON.stringify(meta.info)}`);
			if (meta.metadata?.get("dc:title") !== want.title) fail(`${name}.pdf: XMP's title ${meta.metadata?.get("dc:title")}`);
		}
		await task.destroy();
	}
	console.log(`written: ${Object.keys(expected).length} files read by pdf.js ${pdfjs.version}`);
}

let qpdf = true;
try { execFileSync("qpdf", ["--version"], { stdio: "ignore" }); } catch { qpdf = false; }
if (!qpdf) console.log("written: qpdf not installed: its check skipped");
else for (const f of readdirSync(dir).filter(f => f.endsWith(".pdf"))) {
	try { execFileSync("qpdf", ["--check", path.join(dir, f)], { stdio: "pipe" }); } catch (e) { fail(`${f}: qpdf --check: ${e.stdout}${e.stderr}`); }
}
if (failed > 0) process.exit(1);
