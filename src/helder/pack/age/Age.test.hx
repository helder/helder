package helder.pack.age;

import haxe.io.Bytes;
import helder.pack.age.Age;
import helder.test.Test;
import sys.io.File;

using StringTools;

// age's format (Age) against age's own testkit (C2SP CCTV's vectors,
// tests/pack/age-testkit: the X25519 ones, the header's, STREAM's; not
// scrypt's, armor's or the post-quantum hybrid's): each file's outcome
// (success, no match, HMAC failure, header failure, payload failure) and
// the SHA-256 of what decrypted, a failed payload's part too. Then files
// encrypted here decrypted back: sizes around STREAM's 64 KiB chunks,
// several recipients, a wrong identity.
function tests() {
	final dir = "tests/pack/age-testkit";

	test("age's testkit: every X25519, header and STREAM vector", () -> {
		// (index.txt names them: WASI's directory listing is not every host's)
		var names = [for (l in File.getContent('$dir/index.txt').split("\n")) if (l.trim() != "") l.trim()];
		var ran = 0;
		for (name in names) {
			var raw = File.getBytes('$dir/$name');
			// (the vector's fields, an empty line, the age file)
			var at = 0, fields = new Map<String, Array<String>>();
			while (true) {
				var nl = at;
				while (raw.get(nl) != "\n".code) nl++;
				var l = raw.getString(at, nl - at);
				at = nl + 1;
				if (l == "") break;
				var c = l.indexOf(": ");
				var k = l.substr(0, c);
				if (!fields.exists(k)) fields.set(k, []);
				fields.get(k).push(l.substr(c + 2));
			}
			var file = raw.sub(at, raw.length - at);
			function one(k:String):Null<String>
				return fields.exists(k) ? fields.get(k)[0] : null;
			if (one("compressed") == "zlib") file = haxe.zip.InflateImpl.run(new haxe.io.BytesInput(file));
			var expect = one("expect"), payload = one("payload");
			var got = "success", plain:Null<Bytes> = null;
			try plain = Age.decrypt(file, fields.get("identity") ?? []) catch (e:AgeError) {
				got = e.kind;
				plain = e.partial;
			}
			equals(got, expect, name);
			if (payload != null) equals(haxe.crypto.Sha256.make(plain ?? Bytes.alloc(0)).toHex(), payload, '$name: the payload');
			ran++;
		}
		equals(ran, 67);
	});

	test("encrypted and decrypted back: STREAM's chunk boundaries", () -> {
		var id = Age.generate();
		assert(id.startsWith("AGE-SECRET-KEY-1"));
		var r = Age.recipientOf(id);
		assert(r.startsWith("age1"));
		for (n in [0, 1, 65535, 65536, 65537, 2 * 65536 + 7]) {
			var p = Bytes.alloc(n);
			for (i in 0...n) p.set(i, (i * 31 + 7) & 0xff);
			var f = Age.encrypt(p, [r]);
			// (a header, the nonce, a tag a chunk)
			var chunks = n == 0 ? 1 : Std.int((n + 65535) / 65536);
			equals(Age.decrypt(f, [id]).compare(p), 0, 'size $n');
			assert(f.length > n + 16 + 16 * chunks, 'size $n');
		}
	});

	test("several recipients, each identity opens it; another is no match", () -> {
		var a = Age.generate(), b = Age.generate(), c = Age.generate();
		var f = Age.encrypt(Bytes.ofString("upload key"), [Age.recipientOf(a), Age.recipientOf(b)]);
		equals(f.getString(0, 22), "age-encryption.org/v1\n");
		equals(Age.decrypt(f, [a]).toString(), "upload key");
		equals(Age.decrypt(f, [c, b]).toString(), "upload key");
		var e:AgeError = throws(() -> Age.decrypt(f, [c]));
		equals(e.kind, "no match");
		// (a byte of the payload changed: its chunk refused)
		f.set(f.length - 1, f.get(f.length - 1) ^ 1);
		var e:AgeError = throws(() -> Age.decrypt(f, [a]));
		equals(e.kind, "payload failure");
	});

	test("recipients files and keys: comments, blank lines, refusals", () -> {
		var r = Age.recipientOf("AGE-SECRET-KEY-1EGTZVFFV20835NWYV6270LXYVK2VKNX2MMDKWYKLMGR48UAWX40Q2P2LM0");
		equals(Age.recipients('# the team\n\n$r\n  \n'), [r]);
		equals(Std.string(throws(() -> Age.recipients("# a\nage1nope\n"))).indexOf("line 2: "), 0);
		throws(() -> Age.recipients(r.toUpperCase()));
		throws(() -> Age.secret("AGE-SECRET-KEY-1"));
		throws(() -> Age.secret(r));
	});
}
