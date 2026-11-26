// tests/fixtures/text/text.pdf: two Letter pages of text for the viewer's
// selection: page 1 two paragraphs in Helvetica (every character 0.5 em
// wide), page 2 turned (/Rotate 90) with a line up its side and a Type 3
// font with no ToUnicode (three codes that map to nothing, then "and"):
// node tests/textpdf.mjs tests/fixtures/text/text.pdf
import { writeFileSync } from "node:fs";

const lines = (x, y, pt, ls) => `BT /F1 ${pt} Tf ${pt * 1.4} TL ${x} ${y} Td ` + ls.map((l, i) => `(${l}) ${i ? "'" : "Tj"}`).join(" ") + " ET";
const pages = [
	[
		lines(72, 700, 12, ["The quick brown fox", "jumps over the lazy dog."]),
		lines(72, 600, 12, ["A second paragraph", "of two lines."]),
	],
	[
		lines(72, 500, 12, ["A turned page"]),
		"BT /F1 12 Tf 0 1 -1 0 300 100 Tm (Up the side) Tj ET",
		"BT /F2 12 Tf 72 400 Td <010203> Tj ( and) Tj ET",
	],
];
const widths = Array(95).fill(500).join(" ");
const objs = [];
const add = (s) => (objs.push(s), objs.length);
const catalog = add(null), tree = add(null);
const f1 = add(`<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /FirstChar 32 /LastChar 126 /Widths [${widths}] >>`);
const glyph = add("<< /Length 34 >>\nstream\n600 0 d0 0 0 500 500 re f\nendstream");
const procs = add(`<< /g1 ${glyph} 0 R /g2 ${glyph} 0 R /g3 ${glyph} 0 R /space ${glyph} 0 R /a ${glyph} 0 R /d ${glyph} 0 R /n ${glyph} 0 R >>`);
const f2 = add(`<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs ${procs} 0 R `
	+ `/Encoding << /Differences [1 /g1 /g2 /g3 32 /space 97 /a 100 /d 110 /n] >> /FirstChar 1 /LastChar 110 /Widths [${Array(110).fill(600).join(" ")}] >>`);
const kids = pages.map((ops, i) => {
	const s = ops.join("\n");
	const content = add(`<< /Length ${s.length} >>\nstream\n${s}\nendstream`);
	return add(`<< /Type /Page /Parent ${tree} 0 R /MediaBox [0 0 612 792] /Rotate ${i * 90} /Contents ${content} 0 R /Resources << /Font << /F1 ${f1} 0 R /F2 ${f2} 0 R >> >> >>`);
});
objs[catalog - 1] = `<< /Type /Catalog /Pages ${tree} 0 R >>`;
objs[tree - 1] = `<< /Type /Pages /Kids [${kids.map((k) => `${k} 0 R`).join(" ")}] /Count ${kids.length} >>`;
let out = "%PDF-1.4\n";
const offsets = [];
objs.forEach((o, i) => {
	offsets.push(out.length);
	out += `${i + 1} 0 obj\n${o}\nendobj\n`;
});
const xref = out.length;
out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n`;
for (const o of offsets) out += `${String(o).padStart(10, "0")} 00000 n \n`;
out += `trailer\n<< /Size ${objs.length + 1} /Root ${catalog} 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
writeFileSync(process.argv[2], out, "latin1");
