// The harbour's frames (tests/bench/harbour, `helder run --headless
// --stats`, 8 s of its clock): each run's median, p95 and longest ms (from
// frame 5), the frames over 16.7 ms, draws by pass and GC bytes a frame,
// then the least median and p95 of the runs (the Mac is shared: a run's
// frames wait on other programs; the least is the program's own).
//   node tests/bench/harbour.mjs <stats.json>... [--markdown]
import { readFileSync } from 'node:fs';

const args = process.argv.slice(2), markdown = args.includes('--markdown');
const pct = (a, p) => {
	const s = [...a].sort((x, y) => x - y);
	return s[Math.min(s.length - 1, Math.floor(p * (s.length - 1) + 0.5))];
};
const r = x => Math.round(x * 100) / 100;
const rows = args.filter(a => a !== '--markdown').map(path => {
	const fs = JSON.parse(readFileSync(path, 'utf8')).frames.filter(f => f.frame >= 5);
	const ms = fs.map(f => f.ms), f = fs[fs.length >> 1];
	return {frames: fs.length, median: pct(ms, 0.5), p95: pct(ms, 0.95), max: Math.max(...ms), over: ms.filter(m => m > 1000 / 60).length,
		ui: pct(fs.map(f => f.uiMs), 0.5), draws: f.draws, main: f.sceneDraws, shadow: f.shadowDraws, prepass: f.prepassDraws, gc: pct(fs.map(f => f.gcBytes), 0.5)};
});
const best = {median: Math.min(...rows.map(x => x.median)), p95: Math.min(...rows.map(x => x.p95))};
if (markdown) {
	console.log('| run | frames | median ms | p95 ms | max ms | over 16.7 ms | uiMs median | draws (main, shadow, prepass) | GC bytes/frame |');
	console.log('| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |');
	rows.forEach((x, i) => console.log(`| ${i + 1} | ${x.frames} | ${r(x.median)} | ${r(x.p95)} | ${r(x.max)} | ${x.over} | ${r(x.ui)} | ${x.draws} (${x.main}, ${x.shadow}, ${x.prepass}) | ${x.gc} |`));
	console.log(`\nThe least of ${rows.length}: median ${r(best.median)} ms, p95 ${r(best.p95)} ms.`);
} else {
	rows.forEach((x, i) => console.log(`harbour-bench: run ${i + 1}: ${x.frames} frames, median ${r(x.median)} ms, p95 ${r(x.p95)} ms, max ${r(x.max)} ms (${x.over} over 16.7 ms), ui ${r(x.ui)} ms, draws ${x.draws} (main ${x.main}, shadow ${x.shadow}, prepass ${x.prepass}), ${x.gc} GC bytes a frame`));
	console.log(`harbour-bench: the least of ${rows.length}: median ${r(best.median)} ms, p95 ${r(best.p95)} ms`);
}
