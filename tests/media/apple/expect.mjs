// What ffmpeg decodes in the decoding tests' files (MediaAppleCheck.hx's
// decoded.json; CI has no ffmpeg): each video's frames in presentation
// order, the CRC-32 of their planes as the system's decoder gives them
// (NV12 or P010, rows packed; edit lists ignored: every frame decoded);
// each audio track's frames, its first channel sampled every 97 frames.
// Opus is libopus's (ffmpeg 9's own decoder is off): a WebM's as ffmpeg
// trims it (CodecDelay, DiscardPadding); an MP4's decoded whole
// (skip_manual: ffmpeg skips its pre-skip as the edit list has it, in the
// track's timescale, as if 48 kHz samples), then trimmed by OpusHead's
// pre-skip (an Ogg copy's) and to the edit's duration.
//   node tests/media/apple/expect.mjs   (from the repository's root, or fixtures.sh)
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const here = path.dirname(new URL(import.meta.url).pathname), media = path.join(here, '..');
const run = (cmd, args) => execFileSync(cmd, args, {maxBuffer: 1 << 30});
const table = Array.from({length: 256}, (_, n) => {
	let c = n;
	for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
	return c >>> 0;
});
const crc = b => {
	let c = 0xFFFFFFFF;
	for (const x of b) c = table[(c ^ x) & 255] ^ (c >>> 8);
	return (c ^ 0xFFFFFFFF) >>> 0;
};
const probe = (file, what) => JSON.parse(run('ffprobe', ['-v', 'error', '-of', 'json', ...what, file]).toString());

function video(file) {
	const s = probe(file, ['-select_streams', 'v:0', '-show_entries', 'stream=width,height,pix_fmt']).streams[0];
	const deep = s.pix_fmt.includes('10'), size = s.width * s.height * (deep ? 2 : 1) * 3 / 2;
	const raw = run('ffmpeg', ['-v', 'error', ...(/\.(mp4|mov)$/.test(file) ? ['-ignore_editlist', '1'] : []), '-noautorotate', '-i', file, '-map', '0:v:0', '-fps_mode', 'passthrough', '-f', 'rawvideo', '-pix_fmt', deep ? 'p010le' : 'nv12', '-']);
	const crcs = [];
	for (let at = 0; at + size <= raw.length; at += size) crcs.push(crc(raw.subarray(at, at + size)));
	return {width: s.width, height: s.height, bits: deep ? 10 : 8, crcs};
}

function audio(file, n, codec) {
	const mp4 = /\.mp4$/.test(file), opus = codec === 'opus';
	const args = ['-v', 'quiet', ...(opus ? [`-c:a:${n}`, 'libopus'] : []), ...(opus && mp4 ? [`-flags2:a:${n}`, '+skip_manual'] : []), '-i', file, '-map', `0:a:${n}`];
	const s = probe(file, ['-select_streams', `a:${n}`, '-show_entries', 'stream=channels,sample_rate,duration']).streams[0];
	const raw = run('ffmpeg', [...args, '-f', 'f32le', '-']);
	let all = new Float32Array(raw.buffer, raw.byteOffset, raw.length / 4);
	if (opus && mp4) {
		const ogg = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'helder-opus-')), 'a.opus');
		run('ffmpeg', ['-v', 'error', '-y', '-i', file, '-map', `0:a:${n}`, '-c', 'copy', ogg]);
		const skip = +probe(ogg, ['-show_entries', 'stream=initial_padding']).streams[0].initial_padding;
		all = all.subarray(skip * s.channels, (skip + Math.round(s.duration * 48000)) * s.channels);
	}
	const samples = [];
	for (let i = 0; i * s.channels < all.length; i += 97) samples.push(Math.round(all[i * s.channels] * 1e6) / 1e6);
	return {codec, rate: +s.sample_rate, frames: all.length / s.channels, samples};
}

// (a frame as ffmpeg turns it into RGB, upright)
function rgb(file, frame, matrix, range) {
	const s = probe(file, ['-select_streams', 'v:0', '-show_entries', 'stream=width,height:stream_side_data=rotation']).streams[0];
	const turned = Math.abs(s.side_data_list?.[0]?.rotation ?? 0) % 180 == 90, w = turned ? s.height : s.width, h = turned ? s.width : s.height;
	const raw = run('ffmpeg', ['-v', 'error', ...(/\.(mp4|mov)$/.test(file) ? ['-ignore_editlist', '1'] : []), '-i', file, '-map', '0:v:0', '-fps_mode', 'passthrough',
		'-sws_flags', 'bilinear+accurate_rnd+full_chroma_int', '-vf', `scale=in_color_matrix=${matrix}:in_range=${range}:out_range=pc,format=rgb24`, '-f', 'rawvideo', '-']);
	// (pixels where the picture is flat, its 3x3 neighbours within 2 levels: chroma's
	// upsampling and siting, ours and swscale's, differ at edges)
	const at = frame * w * h * 3, px = (x, y, c) => raw[at + (y * w + x) * 3 + c], pixels = [];
	for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) {
		let flat = true;
		for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) for (let c = 0; c < 3; c++) if (Math.abs(px(x + dx, y + dy, c) - px(x, y, c)) > 2) flat = false;
		if (flat && (x + y * 3) % 7 == 0) pixels.push(x, y, px(x, y, 0), px(x, y, 1), px(x, y, 2));
	}
	return {frame, width: w, height: h, pixels};
}

const out = {video: {}, audio: {}, rgb: {}};
out.rgb['h264-aac.mp4'] = rgb(path.join(media, 'h264-aac.mp4'), 4, 'bt601', 'tv');
out.rgb['rotated.mp4'] = rgb(path.join(media, 'rotated.mp4'), 4, 'bt601', 'tv');
out.rgb['apple/h264-full.mp4'] = rgb(path.join(media, 'apple/h264-full.mp4'), 2, 'bt709', 'pc');
out.rgb['apple/hevc10.mp4'] = rgb(path.join(media, 'apple/hevc10.mp4'), 2, 'bt2020', 'tv');
for (const f of ['h264-aac.mp4', 'hevc.mp4', 'editlist.mov', 'rotated.mp4', 'fragmented.mp4', 'av1.webm', 'av1.mp4', 'apple/vp9-yuv.webm', 'apple/hevc10.mp4', 'apple/h264-full.mp4', 'apple/quads.mp4'])
	out.video[f] = video(path.join(media, f));
for (const [f, codecs] of [['apple/chirp.mp4', ['aac', 'mp3', 'flac', 'alac', 'opus']], ['apple/chirp.mkv', ['vorbis']], ['apple/vp9-yuv.webm', ['opus']]])
	codecs.forEach((c, n) => out.audio[`${f}:${n}`] = audio(path.join(media, f), n, c));
fs.writeFileSync(path.join(here, 'decoded.json'), JSON.stringify(out, null, '\t').replace(/\[\n\t+([-\d.e,\s]+)\n\t+\]/g, (_, l) => `[${l.replace(/\s+/g, ' ').trim()}]`) + '\n');
