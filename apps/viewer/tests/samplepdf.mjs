// samples/About Viewer.pdf: three A4 pages of the web build's sample folder,
// Helvetica's text and two of its photos (JPEGs as they are, DCTDecode):
// node tests/samplepdf.mjs "samples/About Viewer.pdf" a.jpg b.jpg
// (a.jpg, b.jpg: the samples' Murmuration and Planet, about 900 pixels wide)
import { readFileSync, writeFileSync } from "node:fs";

const [out, ...photos] = process.argv.slice(2);
const size = (b) => {
	for (let i = 2; i < b.length; ) {
		const m = b[i + 1], n = b.readUInt16BE(i + 2);
		if (m >= 0xc0 && m <= 0xc3) return { w: b.readUInt16BE(i + 7), h: b.readUInt16BE(i + 5) };
		i += 2 + n;
	}
};
const esc = (s) => s.replace(/[\\()]/g, (c) => "\\" + c);
const text = (x, y, pt, lines, lead = pt * 1.4) => `BT /F1 ${pt} Tf ${lead} TL ${x} ${y} Td ` + lines.map((l, i) => `(${esc(l)}) ${i ? "'" : "Tj"}`).join(" ") + " ET";
const W = 595, H = 842;
const pages = [
	[
		"0.09 0.09 0.1 rg 0 0 595 842 re f 1 1 1 rg",
		text(56, 740, 44, ["Viewer"]),
		"0.75 0.75 0.78 rg",
		text(56, 690, 15, ["A file browser and image viewer, built on helder alone."]),
		"0.9 0.9 0.92 rg",
		text(56, 600, 12, [
			"Browse a folder of photos, PDFs and videos as a grid of thumbnails",
			"or a list, open any of them full size, and step through the folder",
			"from there. On the web it opens on this sample folder; in a Chromium",
			"browser, Open folder shows one of yours, read in the browser only.",
			"",
			"This document has three pages. Scroll down, or press ] for the next.",
		], 19),
	],
	[
		"1 1 1 rg 0 0 595 842 re f 0.1 0.1 0.12 rg",
		text(56, 770, 22, ["Murmuration"]),
		{ photo: 0, x: 56, y: 140, w: 483 },
		"0.35 0.35 0.4 rg",
		text(56, 110, 11, ["Starlings at dusk: examples/murmuration, rendered by helder."]),
	],
	[
		"1 1 1 rg 0 0 595 842 re f 0.1 0.1 0.12 rg",
		text(56, 770, 22, ["Planet"]),
		{ photo: 1, x: 56, y: 400, w: 483 },
		"0.35 0.35 0.4 rg",
		text(56, 370, 11, ["examples/planet, rendered by helder."]),
	],
];
const objs = [];
const add = (s) => (objs.push(s), objs.length);
const catalog = add(null), tree = add(null), font = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>");
const images = photos.map((p) => {
	const b = readFileSync(p), s = size(b);
	return { ...s, id: add({ dict: `<< /Type /XObject /Subtype /Image /Width ${s.w} /Height ${s.h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${b.length} >>`, data: b }) };
});
const kids = pages.map((parts) => {
	const ops = parts.map((p) => {
		if (typeof p == "string") return p;
		const im = images[p.photo], h = (p.w * im.h) / im.w;
		return `q ${p.w} 0 0 ${h.toFixed(1)} ${p.x} ${p.y} cm /Im${p.photo} Do Q`;
	}).join("\n");
	const content = add(`<< /Length ${Buffer.byteLength(ops, "latin1")} >>\nstream\n${ops}\nendstream`);
	const xo = images.map((im, i) => `/Im${i} ${im.id} 0 R`).join(" ");
	return add(`<< /Type /Page /Parent ${tree} 0 R /MediaBox [0 0 ${W} ${H}] /Contents ${content} 0 R /Resources << /Font << /F1 ${font} 0 R >> /XObject << ${xo} >> >> >>`);
});
objs[catalog - 1] = `<< /Type /Catalog /Pages ${tree} 0 R >>`;
objs[tree - 1] = `<< /Type /Pages /Kids [${kids.map((k) => `${k} 0 R`).join(" ")}] /Count ${kids.length} >>`;
const parts = [Buffer.from("%PDF-1.4\n%\xe2\xe3\xcf\xd3\n", "latin1")];
let at = parts[0].length;
const offsets = [];
const put = (b) => (parts.push(b), (at += b.length));
objs.forEach((o, i) => {
	offsets.push(at);
	if (typeof o == "string") put(Buffer.from(`${i + 1} 0 obj\n${o}\nendobj\n`, "latin1"));
	else {
		put(Buffer.from(`${i + 1} 0 obj\n${o.dict}\nstream\n`, "latin1"));
		put(o.data);
		put(Buffer.from("\nendstream\nendobj\n", "latin1"));
	}
});
const xref = at;
put(Buffer.from(`xref\n0 ${objs.length + 1}\n0000000000 65535 f \n` + offsets.map((o) => `${String(o).padStart(10, "0")} 00000 n \n`).join("") +
	`trailer\n<< /Size ${objs.length + 1} /Root ${catalog} 0 R >>\nstartxref\n${xref}\n%%EOF\n`, "latin1"));
writeFileSync(out, Buffer.concat(parts));
