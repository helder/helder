// Audit G 1: one teardown verb per meaning.
//
//   close()    what a program opens or connects to and later ends: windows,
//              popups and menus, players and media, byte sources, sockets,
//              servers, WebSockets, processes, watchers, timers, channels,
//              audio outputs, documents
//   dispose()  what a program owns and gives back: GPU devices, buffers,
//              textures, passes, models, canvases, layers, memory, scopes
//
// Everything already followed it but the media and image memory and the
// story's frames: ImageMemory.free, AudioBuffer.free, AudioRing.free,
// VideoFrame.release (its picture back to the decoder's pool) and
// story's Frame.free(device) are dispose. (free stays a raw pointer's,
// helder/native's Script.free and hxmc's Buffer.free; release a lock's.)
import { edit, done } from "./lib.mjs";

const ONLY = (files, fn) => (s, f) => (files.some((p) => (p.endsWith("/") ? f.startsWith(p) : f === p)) ? fn(s, f) : s);
const rules = [
	// ImageMemory
	ONLY(["src/helder/image/ImageMemory.hx"], (s) => s.replace("@:hxmc.unsafe(gc) public function free() {", "@:hxmc.unsafe(gc) public function dispose() {")
		.replace("result's buffer (take) and frees the rest (free).", "result's buffer (take) and frees the rest (dispose).")),
	ONLY(["src/helder/image/ImageMemory.test.hx", "apps/viewer/src/viewer/Decode.hx", "apps/viewer/src/viewer/Thumbnails.hx"], (s) => s.replace(/\bmem\.free\(\)/g, "mem.dispose()")),
	ONLY(["tests/image/unsafe.txt"], (s) => s.replace("src/helder/image/ImageMemory.hx: @:hxmc.unsafe(gc) public function free() {", "src/helder/image/ImageMemory.hx: @:hxmc.unsafe(gc) public function dispose() {")),
	ONLY(["tests/bench/ImageBench.hx"], (s) => s.replace(/\bm\.free\(\)/g, "m.dispose()")),
	ONLY(["src/helder/image/README.md"], (s) => s.replace("`free` frees the rest.", "`dispose` frees the rest.")),
	// AudioBuffer, AudioRing
	ONLY(["src/helder/media/AudioBuffer.hx", "src/helder/media/AudioRing.hx"], (s) => s.replace("\tpublic function free() {", "\tpublic function dispose() {")),
	ONLY(["src/helder/media/Player.hx"], (s) => s.replace("if (ring != null) ring.free();", "if (ring != null) ring.dispose();").replace(/\bpcm\.free\(\);/, "pcm.dispose();")),
	ONLY(["tests/media/"], (s) => (/new AudioBuffer\(/.test(s) ? s.replace(/\bbuf\.free\(\);/g, "buf.dispose();") : s)),
	// VideoFrame
	ONLY(["src/helder/media/VideoFrame.hx"], (s) => s.replace("\tpublic function release() {", "\tpublic function dispose() {").replace("held until release().", "held until dispose().")),
	ONLY(["src/helder/media/", "tests/media/", "apps/viewer/src/viewer/Thumbs.hx"], (s) =>
		s.replace(/\b(f|fr|shown|frames\[\w+\]|retired\.shift\(\))\.release\(\)/g, "$1.dispose()")),
	ONLY(["src/helder/media/README.md"], (s) => s.replace("image held until `release()`)", "image held until `dispose()`)")),
	// story's Frame
	ONLY(["src/helder/story/NativeHost.hx"], (s) => s.replace("\tpublic function free(device:Device) {", "\tpublic function dispose(device:Device) {").replace(/\bx\.free\(device\)/g, "x.dispose(device)")),
];
edit(() => true, (s, f) => rules.reduce((t, r) => r(t, f), s));
done("01-dispose");
