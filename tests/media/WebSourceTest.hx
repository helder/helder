import haxe.crypto.Crc32;
import helder.async.Async;
import helder.media.*;

// helder.media's WebSource in headless Chromium (browser.mjs runs it, with
// src/helder/media/imports.mjs): an MP4 by Range requests (its packets
// against ffprobe's CRC-32s; browser.mjs counts what the server sent until
// opened.mark is asked for), a
// server that ignores Range, a Blob the page gave, a file in OPFS, a URL
// that is not there. Prints "ok" and the number of checks; exits 1 on a
// failure.
class WebSourceTest {
	static var checks = 0;
	static var failures = 0;

	static function eq<T>(got:T, want:T, what:String) {
		checks++;
		if (got != want) {
			failures++;
			Sys.println('FAIL $what: got $got, want $want');
		}
	}

	static function main() {
		// (each read a request of its own: the demuxer's own reads counted)
		WebSource.block = 1;
		Async.main(task -> {
			// (open and one packet: the moov and a frame, not the file; browser.mjs checks the bytes sent)
			var m = Media.open(WebSource.url("tests/media/h264-aac.mp4"));
			eq(m.tracks.length, 2, "an MP4's tracks by Range requests");
			var s = m.seek(0.45);
			eq(s[0].drop, 4, "its seek");
			// (the server counts the MP4's bytes up to this request)
			helder.async.Fetch.bytes("opened.mark");
			eq(crc(m.read(m.next())), "96b1e1aa", "its keyframe's bytes");
			var whole = Media.open(WebSource.url("tests/media/h264-aac.mp4"));
			var crcs = [], p;
			while ((p = whole.next()) != null) crcs.push(crc(whole.read(p)));
			crcs.sort(Reflect.compare);
			eq(crcs.length, 19, "every packet");
			eq(crcs.join(","), Sys.getEnv("CRCS"), "every packet's bytes, as ffprobe's");
			for (kind in ["whole", "blob", "opfs"]) {
				var source = switch kind {
					case "whole": WebSource.url("whole/tests/media/vp9-opus.webm");
					case "blob": WebSource.blob("clip");
					case _: WebSource.opfs("media/clip.webm");
				}
				var m = Media.open(source);
				var s = m.seek(0.75);
				eq('${s[0].packet.pts} ${s[0].drop} ${s[1].packet.pts}', "500 2 734", "a WebM's seek: " + kind);
				var k = 0;
				while (m.next() != null) k++;
				eq(k, 19, "its packets from there");
			}
			eq(try {
				WebSource.url("tests/media/missing.mp4");
				"opened";
			} catch (e:MediaError) "failed", "failed", "a URL not there");
			Async.yield();
			eq(try {
				WebSource.blob("none");
				"opened";
			} catch (e:MediaError) "failed", "failed", "a Blob not given");
			Async.yield();
			Sys.println(failures == 0 ? 'ok ($checks checks)' : '$failures of $checks checks failed');
			Sys.exit(failures == 0 ? 0 : 1);
		});
	}

	static function crc(b:haxe.io.Bytes):String
		return StringTools.hex(Crc32.make(b), 8).toLowerCase();
}
