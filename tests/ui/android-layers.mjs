// Two screencaps (PNG, RGBA or RGB, 8 bits) of android-layers.sh compared:
// SurfaceControl's layers against the textured compositor, the status bar
// (its clock) and the navigation bar left out. Every pixel within LEVELS
// (glyphs' edges in the list's layer: 6 at most on the emulator) but for
// at most 0.1% of them: the moving box's anti-aliased edge, a pixel wide,
// as the compositor composes a mover against the program's own paint (up
// to about 110 levels there; Apple's layers show it too).
// With a probe x,y,rgb: a's pixel there is rgb (a node's system layer,
// one level off what its node draws under it).
//   node tests/ui/android-layers.mjs <a.png> <b.png> <name> [x,y,rrggbb]
import fs from 'node:fs';
import zlib from 'node:zlib';

const LEVELS = 8;
const [a, b, name, probe] = process.argv.slice(2);

function png(file) {
	const buf = fs.readFileSync(file);
	let at = 8, width = 0, height = 0, type = 0;
	const idat = [];
	while (at < buf.length) {
		const len = buf.readUInt32BE(at), kind = buf.toString('ascii', at + 4, at + 8), data = buf.subarray(at + 8, at + 8 + len);
		if (kind === 'IHDR') {
			width = data.readUInt32BE(0);
			height = data.readUInt32BE(4);
			type = data[9];
		} else if (kind === 'IDAT') idat.push(data);
		at += 12 + len;
	}
	const bpp = type === 6 ? 4 : 3, raw = zlib.inflateSync(Buffer.concat(idat)), stride = width * bpp;
	const px = Buffer.alloc(width * height * 4);
	let prev = Buffer.alloc(stride);
	for (let y = 0; y < height; y++) {
		const f = raw[y * (stride + 1)], line = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
		for (let x = 0; x < stride; x++) {
			const l = x >= bpp ? line[x - bpp] : 0, u = prev[x], ul = x >= bpp ? prev[x - bpp] : 0;
			let p = 0;
			if (f === 1) p = l;
			else if (f === 2) p = u;
			else if (f === 3) p = (l + u) >> 1;
			else if (f === 4) {
				const q = l + u - ul, pa = Math.abs(q - l), pb = Math.abs(q - u), pc = Math.abs(q - ul);
				p = pa <= pb && pa <= pc ? l : pb <= pc ? u : ul;
			}
			line[x] = (line[x] + p) & 0xff;
		}
		for (let x = 0; x < width; x++)
			for (let k = 0; k < 4; k++) px[(y * width + x) * 4 + k] = k < bpp ? line[x * bpp + k] : 255;
		prev = line;
	}
	return { width, height, px };
}

const A = png(a), B = png(b);
if (A.width !== B.width || A.height !== B.height) {
	console.log(`android-layers.mjs: ${name}: FAIL: ${A.width}x${A.height} against ${B.width}x${B.height}`);
	process.exit(1);
}
// (the bars: the status bar's top 6%, the navigation bar's bottom 5%)
const y0 = Math.round(A.height * 0.06), y1 = Math.round(A.height * 0.95);
let differ = 0, over2 = 0, over = 0, max = 0;
for (let y = y0; y < y1; y++)
	for (let x = 0; x < A.width; x++) {
		const i = (y * A.width + x) * 4;
		let d = 0;
		for (let k = 0; k < 3; k++) d = Math.max(d, Math.abs(A.px[i + k] - B.px[i + k]));
		if (d > 0) differ++;
		if (d > 2) over2++;
		if (d > LEVELS) over++;
		max = Math.max(max, d);
	}
const total = A.width * (y1 - y0), ok = over <= total * 0.001;
console.log(`android-layers.mjs: ${name}: ${ok ? 'ok' : 'FAIL'}: ${differ} of ${total} pixels differ, ${over2} by more than 2 levels, ${over} by more than ${LEVELS}, at most ${max}`);
let shown = true;
if (probe) {
	const [x, y, rgb] = probe.split(','), i = (Number(y) * A.width + Number(x)) * 4, want = parseInt(rgb, 16);
	const got = [A.px[i], A.px[i + 1], A.px[i + 2]];
	shown = got.every((v, k) => Math.abs(v - ((want >> (16 - 8 * k)) & 0xff)) <= 1);
	console.log(`android-layers.mjs: ${name}: the system layer at ${x},${y}: ${shown ? 'ok' : 'FAIL'} (${got.join(' ')})`);
}
process.exit(ok && shown ? 0 : 1);
