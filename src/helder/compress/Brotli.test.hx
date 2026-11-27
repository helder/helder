package helder.compress;

import haxe.crypto.Sha256;
import haxe.io.Bytes;
import helder.test.Gen;
import helder.test.Test;
import sys.io.File;

using StringTools;

// Brotli against the reference's test vectors (tests/compress/brotli: its
// tests/testdata's streams under 60 KB, and node's encoder's at a small
// window and in text mode; each original's size and SHA-256 in
// manifest.json); a damaged stream an error "Brotli: ...", never another
// exception, a hang or memory past its bound (the fuzz lane soaks it)
function tests() {
	var dir = "tests/compress/brotli";
	var manifest:haxe.DynamicAccess<{size:Int, sha256:String}> = haxe.Json.parse(File.getContent('$dir/manifest.json'));

	describe("Brotli", () -> {
		test("the reference's test vectors", () -> {
			var wrong = [];
			for (name => want in manifest) {
				var got = Brotli.all(File.getBytes('$dir/$name'), 1 << 24);
				if (got.length != want.size || Sha256.make(got).toHex() != want.sha256) wrong.push(name);
			}
			equals(wrong, []);
			assert(manifest.keys().length >= 40);
		});
		test("exact: the size given, else an error", () -> {
			var data = File.getBytes('$dir/alice29.txt.compressed'), size = manifest["alice29.txt.compressed"].size;
			equals(Brotli.exact(data, 0, data.length, size).length, size);
			equals(error(() -> Brotli.exact(data, 0, data.length, size - 1)).startsWith("Brotli: more than"), true);
			equals(error(() -> Brotli.exact(data, 0, data.length, size + 1)), 'Brotli: $size bytes, not ${size + 1}');
			equals(error(() -> Brotli.all(data, 1000)), "Brotli: more than 1000 bytes");
		});
		test("a stream cut short, its padding set, data after it: as the reference refuses them", () -> {
			var data = File.getBytes('$dir/quickfox.compressed');
			for (n in 0...data.length) assert(error(() -> Brotli.all(data.sub(0, n), 1 << 20)).startsWith("Brotli: "), 'cut at $n');
			// (x.compressed: "X")
			equals(Brotli.all(Bytes.ofHex("0b00805803"), 16).toString(), "X");
			equals(error(() -> Brotli.all(Bytes.ofHex("0b00805883"), 16)), "Brotli: padding is not zero");
			equals(error(() -> Brotli.all(Bytes.ofHex("0b0080580300"), 16)), "Brotli: data after the stream");
		});
		test("the static dictionary: RFC 7932's", () -> {
			equals(Sha256.make(helder.asset.Embed.bytes("helder/compress/dictionary.bin")).toHex(), "20e42eb1b511c21806d4d227d07e5dd06877d8ce7b3a817f378f313653f35c70");
		});
		test("a mutated stream: decoded, or an error", () -> {
			var seeds = [for (name in manifest.keys()) if (sys.FileSystem.stat('$dir/$name').size <= 4096) name => File.getBytes('$dir/$name')];
			property(mutated(seeds), b -> {
				var e = error(() -> Brotli.all(b, 1 << 20));
				assert(e == null || e.startsWith("Brotli: "), e);
			}, {cases: 300, seconds: 3, limit: 10, memory: 128});
		});
	});
}

// (what f threw, null when it did not)
function error(f:() -> Void):Null<String>
	return try {
		f();
		null;
	} catch (e:Dynamic) Std.string(e);
