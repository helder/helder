// What ffprobe reads in the media tests' files, for the tests (CI has no
// ffprobe): tests/media/expected.json, each file's streams (codec, sizes,
// rate, channels, rotation, time base, extradata in hex) and its packets
// in ffprobe's order ([stream, pts, dts, duration, size, pos, key, the
// CRC-32 of its bytes]).
//   node tests/media/expect.mjs   (after fixtures.sh)
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const files = fs.readdirSync(dir).filter((f) => /\.(mp4|mov|webm|mkv)$/.test(f)).sort();
const out = {};
const num = (v) => (v === undefined || v === 'N/A' ? null : Number(v));
for (const f of files) {
	const j = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-of', 'json', '-show_data', '-show_data_hash', 'CRC32',
		'-show_entries', 'stream=index,codec_name,codec_type,width,height,sample_rate,channels,time_base,duration,extradata:stream_side_data=rotation:packet=stream_index,pts,dts,duration,size,pos,flags,data_hash',
		path.join(dir, f)], { maxBuffer: 1 << 26 }).toString());
	out[f] = {
		streams: j.streams.map((s) => ({
			codec: s.codec_name, type: s.codec_type, width: s.width ?? 0, height: s.height ?? 0,
			rate: num(s.sample_rate) ?? 0, channels: s.channels ?? 0, timeBase: s.time_base,
			duration: num(s.duration), rotation: s.side_data_list?.find((d) => d.rotation !== undefined)?.rotation ?? 0,
			extradata: (s.extradata ?? '').split('\n').map((l) => l.slice(10, 49).replace(/ /g, '')).join(''),
		})),
		packets: j.packets.map((p) => [p.stream_index, num(p.pts), num(p.dts), num(p.duration), num(p.size), num(p.pos), p.flags[0] === 'K' ? 1 : 0, p.data_hash.slice(6)]),
	};
}
fs.writeFileSync(path.join(dir, 'expected.json'), JSON.stringify(out).replace(/\],\[/g, '],\n[').replace(/"([\w.-]+\.(mp4|mov|webm|mkv))":/g, '\n"$1":') + '\n');
