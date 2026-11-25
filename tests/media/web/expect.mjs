// The browser test's own references (MediaWebCheck.hx's rgb.json; CI has no
// ffmpeg): frames of the videos Linux's Chromium decodes (VP9, AV1; not
// H.264, whose references are decoded.json's) as ffmpeg turns them into RGB,
// at pixels where the picture is flat, as tests/media/apple/expect.mjs does.
//   node tests/media/web/expect.mjs   (from the repository's root)
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const here = path.dirname(new URL(import.meta.url).pathname), media = path.join(here, '..');
const run = (cmd, args) => execFileSync(cmd, args, {maxBuffer: 1 << 30});

function rgb(file, frame, matrix, range) {
	const s = JSON.parse(run('ffprobe', ['-v', 'error', '-of', 'json', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', file]).toString()).streams[0];
	const w = s.width, h = s.height;
	const raw = run('ffmpeg', ['-v', 'error', '-i', file, '-map', '0:v:0', '-fps_mode', 'passthrough', '-sws_flags', 'bilinear+accurate_rnd+full_chroma_int', '-vf',
		`scale=in_color_matrix=${matrix}:in_range=${range}:out_range=pc,format=rgb24`, '-f', 'rawvideo', '-']);
	const at = frame * w * h * 3, px = (x, y, c) => raw[at + (y * w + x) * 3 + c], pixels = [];
	for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) {
		let flat = true;
		for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) for (let c = 0; c < 3; c++) if (Math.abs(px(x + dx, y + dy, c) - px(x, y, c)) > 2) flat = false;
		if (flat && (x + y * 3) % 7 == 0) pixels.push(x, y, px(x, y, 0), px(x, y, 1), px(x, y, 2));
	}
	return {frame, width: w, height: h, pixels};
}

const out = {'apple/vp9-yuv.webm': rgb(path.join(media, 'apple/vp9-yuv.webm'), 2, 'bt601', 'tv'), 'av1.webm': rgb(path.join(media, 'av1.webm'), 4, 'bt601', 'tv')};
fs.writeFileSync(path.join(here, 'rgb.json'), JSON.stringify(out).replace(/\],"/g, '],\n"') + '\n');
