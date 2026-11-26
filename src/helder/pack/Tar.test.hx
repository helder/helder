package helder.pack;

import haxe.io.Bytes;
import helder.pack.Tar.TarEntry;
import helder.test.Gen;
import helder.test.Test;

// The desktop releases' archives: deflate's raw stream (helder.image.Deflate) and gzip's file
// inflated back (haxe.zip's inflate), Zip's deflated entries read back,
// Tar's ustar headers (names, modes, sizes, kinds, the checksum, a long
// name split into its prefix), the same bytes for the same input.
function tests() {
	final text = Bytes.ofString([for (i in 0...400) 'line $i of a text that repeats itself\n'].join(""));
	final noise = Bytes.alloc(3000);
	// (xorshift's bytes: nothing for deflate to find)
	var x = 0x2545F491;
	for (i in 0...noise.length) {
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		noise.set(i, x & 0xff);
	}

	function inflate(raw:Bytes, n:Int):Bytes {
		var out = Bytes.alloc(n);
		var got = new haxe.zip.InflateImpl(new haxe.io.BytesInput(raw), false, false).readBytes(out, 0, n);
		equals(got, n);
		return out;
	}
	function octal(b:Bytes, at:Int, n:Int):Int {
		var v = 0;
		for (i in 0...n) {
			var c = b.get(at + i);
			if (c < "0".code || c > "7".code) break;
			v = v * 8 + c - "0".code;
		}
		return v;
	}

	test("deflate: raw and gzip, inflated back", () -> {
		var raw = helder.image.Deflate.raw(text);
		assert(raw.length < text.length / 4, "a text shrinks");
		equals(inflate(raw, text.length).compare(text), 0);
		var gz = Tar.gzip(text);
		equals([gz.get(0), gz.get(1), gz.get(2)], [0x1f, 0x8b, 8]);
		equals(gz.getInt32(gz.length - 8), haxe.crypto.Crc32.make(text));
		equals(gz.getInt32(gz.length - 4), text.length);
		equals(inflate(gz.sub(10, gz.length - 18), text.length).compare(text), 0);
	});
	test("zip: deflated entries read back, the incompressible stored", () -> {
		var z = Zip.stored([
			{name: "a.txt", data: text, align: 1, mode: 0x1a4, deflate: true},
			{name: "noise", data: noise, align: 1, deflate: true},
			{name: "plain", data: text, align: 1}
		]);
		var es = Zip.read(z);
		equals([for (e in es) e.method], [8, 0, 0]);
		equals(es[0].data.compare(text), 0);
		equals(es[0].mode, 0x1a4);
		equals(es[1].data.compare(noise), 0);
		assert(z.length < text.length * 2 + noise.length, "smaller than stored");
	});
	test("tar: ustar headers, data padded to 512, the end", () -> {
		var long = "dir/" + [for (_ in 0...30) "abcd"].join("") + "/file.txt";
		var t = Tar.write([
			{name: "dir"},
			{name: "dir/run", data: Bytes.ofString("#!/bin/sh\n"), mode: 0x1ed},
			{name: "dir/link", link: "run"},
			{name: long, data: text}
		]);
		equals(t.length % 512, 0);
		equals(t.getString(0, 4), "dir/");
		equals(t.get(156), "5".code);
		equals(t.getString(257, 5), "ustar");
		var h = 512;
		equals(t.getString(h, 7), "dir/run");
		equals([octal(t, h + 100, 7), octal(t, h + 124, 11), t.get(h + 156)], [0x1ed, 10, "0".code]);
		var sum = 0;
		for (i in 0...512)
			sum += i >= 148 && i < 156 ? " ".code : t.get(h + i);
		equals(octal(t, h + 148, 6), sum);
		equals(t.getString(h + 512, 10), "#!/bin/sh\n");
		h += 1024;
		equals(t.get(h + 156), "2".code);
		equals(t.getString(h + 157, 3), "run");
		h += 512;
		equals(t.getString(h, 8), "file.txt");
		equals(t.getString(h + 345, long.length - 9), long.substr(0, long.length - 9));
		equals(octal(t, h + 124, 11), text.length);
		equals(t.compare(Tar.write([{name: "dir"}, {name: "dir/run", data: Bytes.ofString("#!/bin/sh\n"), mode: 0x1ed}, {name: "dir/link", link: "run"}, {name: long, data: text}])), 0);
	});
	test("tar: a link past 100 bytes refused, not cut", () -> {
		throws(() -> Tar.write([{name: "a", link: [for (_ in 0...101) "x"].join("")}]));
	});
	test("tar: a long name split where its prefix fits", () -> {
		var name = [for (_ in 0...150) "p"].join("") + "/" + [for (_ in 0...10) "a"].join("") + "/" + [for (_ in 0...10) "b"].join("");
		equals(read(Tar.write([{name: name, data: Bytes.alloc(1)}]))[0].name, name);
	});
	test("tar: any entries read back, or a name too long refused", () -> property(array(entry, 0, 5), entries -> {
		var t = try Tar.write(entries) catch (e:String) {
			assert(Lambda.exists(entries, e -> !fits(e)), 'refused: $e');
			return;
		}
		equals(read(t), [for (e in entries) {name: e.data == null && e.link == null ? e.name + "/" : e.name, data: e.data, mode: e.mode ?? (e.data != null && e.link == null ? 0x1a4 : 0x1ed), link: e.link}]);
	}, {cases: 200}));
	test("gzip and deflate: any bytes inflated back", () -> property(array(oneOf([int(0, 255), pick([0, 97])]), 0, 3000), xs -> {
		var data = Bytes.alloc(xs.length);
		for (i in 0...xs.length)
			data.set(i, xs[i]);
		var gz = Tar.gzip(data);
		equals(gz.getInt32(gz.length - 8), haxe.crypto.Crc32.make(data));
		equals(inflate(gz.sub(10, gz.length - 18), data.length).toHex(), data.toHex());
	}, {cases: 100}));
}

private final segment = oneOf([pick(["a", "bin", "é", "lib"]), string(pick(["x", "é", "y"]), 1, 60), string(constant("p"), 100, 160)]);

private final entry:Gen<TarEntry> = c -> {
	var name = c.draw(array(segment, 1, 5)).join("/");
	var mode = c.draw(oneOf([constant(null), int(0, 0x1ff)]));
	return switch c.draw(int(0, 2)) {
		case 0:
			var b = Bytes.alloc(c.draw(oneOf([int(0, 4), int(0, 1100)])));
			for (i in 0...b.length)
				b.set(i, (i * 31 + name.length) & 0xff);
			{name: name, data: b, mode: mode};
		case 1: {name: name, mode: mode};
		case _: {name: name, link: c.draw(array(segment, 1, 4)).join("/"), mode: mode};
	}
}

// (ustar's limits: a name of 100 bytes, else split at a slash with a prefix of 155)
private function fits(e:TarEntry):Bool {
	var name = e.data == null && e.link == null ? e.name + "/" : e.name;
	if (e.link != null && Bytes.ofString(e.link).length > 100) return false;
	if (Bytes.ofString(name).length <= 100) return true;
	var k = name.length - 1;
	while ((k = name.lastIndexOf("/", k - 1)) > 0)
		if (Bytes.ofString(name.substr(k + 1)).length <= 100 && Bytes.ofString(name.substr(0, k)).length <= 155) return true;
	return false;
}

// (an archive's entries as a reader takes them: each header's checksum checked)
private function read(t:Bytes):Array<{name:String, data:Null<Bytes>, mode:Int, link:Null<String>}> {
	function str(at:Int, max:Int):String {
		var n = 0;
		while (n < max && t.get(at + n) != 0)
			n++;
		return t.getString(at, n);
	}
	function oct(at:Int, n:Int):Int {
		var v = 0;
		for (i in 0...n) {
			var c = t.get(at + i);
			if (c < "0".code || c > "7".code) break;
			v = v * 8 + c - "0".code;
		}
		return v;
	}
	var out = [], h = 0;
	while (h + 512 <= t.length && t.get(h) != 0) {
		var sum = 0;
		for (i in 0...512)
			sum += i >= 148 && i < 156 ? " ".code : t.get(h + i);
		equals(oct(h + 148, 7), sum, "the checksum");
		var prefix = str(h + 345, 155), name = str(h, 100), size = oct(h + 124, 12), kind = t.get(h + 156);
		out.push({
			name: prefix == "" ? name : prefix + "/" + name,
			data: kind == "0".code ? t.sub(h + 512, size) : null,
			mode: oct(h + 100, 8),
			link: kind == "2".code ? str(h + 157, 100) : null
		});
		h += 512 + Std.int(Math.ceil(size / 512)) * 512;
	}
	equals(t.length - h, 1024, "the end");
	return out;
}

