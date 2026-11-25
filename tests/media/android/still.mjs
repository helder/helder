// A screencap of VideoStillCheck (android.sh) checked: quads.mp4's frame at
// 0.2 s contained in the box VideoStillCheck said (x,y,w,h in pixels), each
// quadrant's centre (away from the square moving through the middle)
// within levels of the source's colours as ffmpeg decodes them: drawn,
// the driver's conversion (the emulator's: within 1), 8; the system
// layer's, SurfaceFlinger's, 16: it converts the frame as the codec tagged
// it, SMPTE 170M's transfer onto the sRGB display (the emulator's grey 128
// shows as 141), which MediaCodec sets on each buffer, so helder cannot
// tag it sRGB's as it does Apple's.
//   node tests/media/android/still.mjs <still.png> <x,y,w,h> <name> <levels>
import fs from 'node:fs';
import zlib from 'node:zlib';

const SOURCE = [[254, 0, 0], [0, 255, 1], [0, 0, 255], [128, 128, 128]];
const [file, box, name, levels] = process.argv.slice(2);
const LEVELS = Number(levels);

function png(f) {
	const buf = fs.readFileSync(f);
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
	const px = Buffer.alloc(width * height * 3);
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
		for (let x = 0; x < width; x++) for (let k = 0; k < 3; k++) px[(y * width + x) * 3 + k] = line[x * bpp + k];
		prev = line;
	}
	return { width, px };
}

const { width, px } = png(file);
const [x, y, w, h] = box.split(',').map(Number);
const k = Math.min(w / 64, h / 48), x0 = x + (w - 64 * k) / 2, y0 = y + (h - 48 * k) / 2;
let worst = 0;
const got = [[16, 12], [48, 12], [16, 36], [48, 36]].map(([qx, qy], i) => {
	const at = (Math.round(y0 + (qy + 0.5) * k) * width + Math.round(x0 + (qx + 0.5) * k)) * 3;
	const c = [px[at], px[at + 1], px[at + 2]];
	for (let j = 0; j < 3; j++) worst = Math.max(worst, Math.abs(c[j] - SOURCE[i][j]));
	return c.join(' ');
});
const ok = worst <= LEVELS;
console.log(`still.mjs: ${ok ? 'ok' : 'FAIL'}: ${name}: the quadrants ${got.join(', ')}, at most ${worst} levels off the source (${LEVELS})`);
process.exit(ok ? 0 : 1);
