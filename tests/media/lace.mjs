// Matroska rewritten for the media tests (fixtures.sh), what ffmpeg's
// muxer does not write:
//   node lace.mjs lace <in.mkv> <out.mkv>   consecutive audio SimpleBlocks laced,
//     four frames a block: track 1's Xiph and EBML in turn, track 2's fixed
//   node lace.mjs live <in.webm> <out.webm>  the Segment and Clusters of unknown
//     size, without SeekHead and Cues
// Both drop SeekHead and Cues (their positions would be wrong).
import fs from 'node:fs';

const [mode, input, output] = process.argv.slice(2);
const src = fs.readFileSync(input);

function vint(b, at) {
	let len = 1, mask = 0x80;
	while (len <= 8 && !(b[at] & mask)) { len++; mask >>= 1; }
	let v = b[at] & (mask - 1);
	for (let i = 1; i < len; i++) v = v * 256 + b[at + i];
	return { v, len, unknown: v === 2 ** (7 * len) - 1 };
}
function id(b, at) {
	const { len } = vint(b, at);
	return { id: b.subarray(at, at + len), len };
}
function children(b, start, end) {
	const out = [];
	let at = start;
	while (at < end) {
		const i = id(b, at), s = vint(b, at + i.len);
		const data = at + i.len + s.len;
		out.push({ id: Buffer.from(i.id).toString('hex'), raw: b.subarray(at, data + s.v), data: b.subarray(data, data + s.v) });
		at = data + s.v;
	}
	return out;
}
const size = (n) => {
	const out = Buffer.alloc(8);
	out[0] = 0x01;
	for (let i = 7; i > 0; i--) { out[i] = n % 256; n = Math.floor(n / 256); }
	return out;
};
const UNKNOWN = Buffer.from([0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
const element = (hex, body, unknown) => Buffer.concat([Buffer.from(hex, 'hex'), unknown ? UNKNOWN : size(body.length), body]);
const sizeVint = (n) => {
	for (let len = 1; len <= 8; len++) if (n < 2 ** (7 * len) - 1) {
		const out = Buffer.alloc(len);
		let v = n;
		for (let i = len - 1; i >= 0; i--) { out[i] = v % 256; v = Math.floor(v / 256); }
		out[0] |= 0x80 >> (len - 1);
		return out;
	}
};
const signedVint = (n) => {
	for (let len = 1; len <= 8; len++) {
		const bias = 2 ** (7 * len - 1) - 1;
		if (n >= -bias && n <= bias) {
			const b = Buffer.alloc(len);
			let v = n + bias;
			for (let i = len - 1; i >= 0; i--) { b[i] = v % 256; v = Math.floor(v / 256); }
			b[0] |= 0x80 >> (len - 1);
			return b;
		}
	}
};

// a SimpleBlock's parts: track, timestamp, flags, its frame
function block(data) {
	const t = vint(data, 0);
	return { track: t.v, head: data.subarray(0, t.len), time: data.readInt16BE(t.len), flags: data[t.len + 2], frame: data.subarray(t.len + 3) };
}
function laced(blocks, kind) {
	const b = blocks[0], frames = blocks.map((x) => x.frame);
	const flags = (b.flags & ~0x06) | { xiph: 0x02, fixed: 0x04, ebml: 0x06 }[kind];
	const head = [b.head, Buffer.from([0, 0, flags, frames.length - 1])];
	head[1].writeInt16BE(b.time, 0);
	if (kind === 'xiph')
		for (const f of frames.slice(0, -1)) {
			const s = [];
			let n = f.length;
			while (n >= 255) { s.push(255); n -= 255; }
			s.push(n);
			head.push(Buffer.from(s));
		}
	if (kind === 'ebml') {
		head.push(sizeVint(frames[0].length));
		for (let i = 1; i < frames.length - 1; i++) head.push(signedVint(frames[i].length - frames[i - 1].length));
	}
	return element('a3', Buffer.concat([...head, ...frames]));
}

let turn = 0;
function cluster(c) {
	if (mode === 'live') return element('1f43b675', c.data, true);
	// (each track's blocks in runs, a laced block where its run's first was:
	// other tracks' blocks between them)
	const out = [], runs = new Map();
	const flush = (t) => {
		const r = runs.get(t);
		if (!r) return;
		runs.delete(t);
		const kind = t === 2 ? 'fixed' : turn++ % 2 ? 'ebml' : 'xiph';
		out[r.slot] = r.blocks.length === 1 && r.blocks[0].raw ? element('a3', r.blocks[0].raw) : laced(r.blocks, kind);
	};
	for (const e of children(c.data, 0, c.data.length)) {
		// (a BlockGroup of a Block and its BlockDuration: a frame to lace, its
		// duration the track's default; others, DiscardPadding's, kept)
		const group = e.id === 'a0' ? children(e.data, 0, e.data.length) : null;
		const plain = group && group.length === 2 && group[0].id === 'a1' && group[1].id === '9b';
		if (e.id !== 'a3' && !plain) { out.push(e.raw); continue; }
		const b = plain ? { ...block(group[0].data), raw: null } : { ...block(e.data), raw: e.data }, r = runs.get(b.track);
		if (plain) b.flags |= 0x80;
		if (r && (r.blocks.length === 4 || (b.track === 2 && b.frame.length !== r.blocks[0].frame.length))) flush(b.track);
		if (!runs.has(b.track)) runs.set(b.track, { slot: out.push(null) - 1, blocks: [] });
		runs.get(b.track).blocks.push(b);
	}
	for (const t of [...runs.keys()]) flush(t);
	return element('1f43b675', Buffer.concat(out));
}

const top = children(src, 0, src.length);
const parts = [];
for (const e of top) {
	if (e.id !== '18538067') { parts.push(e.raw); continue; }
	const body = children(e.data, 0, e.data.length)
		.filter((c) => c.id !== '114d9b74' && c.id !== '1c53bb6b' && c.id !== 'ec')
		.map((c) => (c.id === '1f43b675' ? cluster(c) : c.raw));
	parts.push(element('18538067', Buffer.concat(body), mode === 'live'));
}
fs.writeFileSync(output, Buffer.concat(parts));
