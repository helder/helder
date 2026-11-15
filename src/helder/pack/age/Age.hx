package helder.pack.age;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.pack.Entropy;

using StringTools;

// age's file format (https://age-encryption.org/v1) with X25519 recipients,
// in plain Haxe, for helder's credentials (helder.cli.Credentials): what
// `age -r age1...` writes and `age -d -i key.txt` reads, and the reverse.
// The header: `age-encryption.org/v1`, a stanza per recipient (`-> X25519
// <ephemeral share>`, the 16-byte file key sealed by ChaCha20-Poly1305 under
// HKDF-SHA256 of the shared secret), `--- <HMAC of the header>`; then the
// payload: a 16-byte nonce and STREAM, chunks of 64 KiB sealed with a
// counter and the last one's flag. Parsed strictly, as age's testkit
// (C2SP CCTV) has it: canonical base64 without padding, LF alone, every
// stanza's body ended by a short line. No passphrases (scrypt), no armor.
class Age {
	static inline var INTRO = "age-encryption.org/v1";
	static inline var CHUNK = 65536;
	static final B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

	// ---- keys

	// a new identity, `AGE-SECRET-KEY-1...` (the system's random source)
	public static function generate():String
		return Bech32.encode("age-secret-key-", Entropy.bytes(32)).toUpperCase();

	// an identity's recipient, `age1...`
	public static function recipientOf(identity:String):String
		return Bech32.encode("age", X25519.publicKey(secret(identity)));

	public static function secret(identity:String):Bytes {
		var d = try Bech32.decode(identity.trim()) catch (err:String) throw 'not an age secret key (AGE-SECRET-KEY-1...): $err';
		if (d.hrp != "age-secret-key-" || d.data.length != 32) throw "not an age secret key (AGE-SECRET-KEY-1...)";
		return d.data;
	}

	public static function publicKey(recipient:String):Bytes {
		var r = recipient.trim();
		if (r != r.toLowerCase()) throw '$r: not an age public key (age1..., lowercase)';
		var d = try Bech32.decode(r) catch (err:String) throw '$r: not an age public key (age1...): $err';
		if (d.hrp != "age" || d.data.length != 32) throw '$r: not an age public key (age1...)';
		return d.data;
	}

	// a recipients file's keys (age -R's: one a line, # comments, blank lines)
	public static function recipients(text:String):Array<String> {
		var out = [];
		for (i => line in text.split("\n")) {
			var l = line.trim();
			if (l == "" || l.startsWith("#")) continue;
			try publicKey(l) catch (err:String) throw 'line ${i + 1}: $err';
			out.push(l);
		}
		return out;
	}

	// ---- encrypt

	public static function encrypt(plaintext:Bytes, recipients:Array<String>):Bytes {
		if (recipients.length == 0) throw "age: no recipient";
		var fileKey = Entropy.bytes(16);
		var h = new StringBuf();
		h.add(INTRO + "\n");
		for (r in recipients) {
			var pk = publicKey(r);
			var e = Entropy.bytes(32), share = X25519.publicKey(e);
			var shared = X25519.scalarMult(e, pk);
			var body = ChaCha20Poly1305.seal(wrapKey(shared, share, pk), ChaCha20Poly1305.zeros(12), fileKey);
			h.add('-> X25519 ${b64(share)}\n');
			h.add(wrap(b64(body)));
		}
		h.add("---");
		var mac = Hkdf.hmac(Hkdf.derive(fileKey, null, Bytes.ofString("header"), 32), Bytes.ofString(h.toString()));
		h.add(' ${b64(mac)}\n');
		var out = new BytesBuffer();
		out.add(Bytes.ofString(h.toString()));
		var nonce = Entropy.bytes(16);
		out.add(nonce);
		out.add(seal(Hkdf.derive(fileKey, nonce, Bytes.ofString("payload"), 32), plaintext));
		return out.getBytes();
	}

	// ---- decrypt

	// the plaintext; throws an AgeError (its kind: header failure, no match,
	// HMAC failure, payload failure)
	public static function decrypt(file:Bytes, identities:Array<String>):Bytes {
		var h = header(file);
		var fileKey:Null<Bytes> = null;
		var keys = [];
		for (i in identities) {
			var s = secret(i);
			keys.push({s: s, pk: X25519.publicKey(s)});
		}
		for (st in h.stanzas) {
			if (st.args[0] != "X25519") continue;
			if (st.args.length != 2) throw new AgeError("header failure", "an X25519 stanza takes one argument");
			var share = unb64(st.args[1]);
			if (share == null || share.length != 32) throw new AgeError("header failure", "an X25519 share is 32 bytes, canonical base64");
			if (st.body.length != 32) throw new AgeError("header failure", "an X25519 stanza's body is 32 bytes");
			for (k in keys) {
				var shared = X25519.scalarMult(k.s, share);
				if (ChaCha20Poly1305.equal(shared, ChaCha20Poly1305.zeros(32))) throw new AgeError("header failure", "an X25519 share of low order");
				var key = ChaCha20Poly1305.open(wrapKey(shared, share, k.pk), ChaCha20Poly1305.zeros(12), st.body);
				if (key != null) {
					fileKey = key;
					break;
				}
			}
			if (fileKey != null) break;
		}
		if (fileKey == null) throw new AgeError("no match", "no identity matches a recipient of the file");
		var mac = Hkdf.hmac(Hkdf.derive(fileKey, null, Bytes.ofString("header"), 32), file.sub(0, h.macAt));
		if (!ChaCha20Poly1305.equal(mac, h.mac)) throw new AgeError("HMAC failure", "the header's MAC is wrong");
		var key = Hkdf.derive(fileKey, file.sub(h.end, 16), Bytes.ofString("payload"), 32);
		return open(key, file.sub(h.end + 16, file.length - h.end - 16));
	}

	// (the stanzas, the MAC and where the header's MACed part and the whole header end)
	static function header(f:Bytes):{stanzas:Array<{args:Array<String>, body:Bytes}>, mac:Bytes, macAt:Int, end:Int} {
		var at = 0;
		function fail(why:String):Dynamic
			throw new AgeError("header failure", why);
		function line():String {
			var i = at;
			while (i < f.length && f.get(i) != "\n".code) i++;
			if (i >= f.length) fail("the header ends without a newline");
			var s = f.getString(at, i - at);
			for (k in 0...s.length) {
				var c = s.charCodeAt(k);
				if (c < 32 || c > 126) fail("a character out of the header's range (CR, control, non-ASCII)");
			}
			at = i + 1;
			return s;
		}
		if (line() != INTRO) fail("not age-encryption.org/v1 (another version, or not an age file)");
		var stanzas = [];
		while (true) {
			var start = at;
			var l = line();
			if (l.startsWith("--- ")) {
				var mac = unb64(l.substr(4));
				if (mac == null || mac.length != 32) fail("the header's MAC is 32 bytes, canonical base64");
				if (f.length - at < 16) fail("no payload nonce");
				return {stanzas: stanzas, mac: mac, macAt: start + 3, end: at};
			}
			if (!l.startsWith("-> ")) fail("a stanza starts with \"-> \"");
			var args = l.substr(3).split(" ");
			for (a in args) if (a == "") fail("an empty stanza argument");
			var text = new StringBuf();
			while (true) {
				var b = line();
				if (b.length > 64) fail("a stanza's body line longer than 64 columns");
				for (k in 0...b.length) if (B64.indexOf(b.charAt(k)) < 0) fail("a stanza's body is base64");
				text.add(b);
				if (b.length < 64) break;
			}
			var body = unb64(text.toString());
			if (body == null) fail("a stanza's body is canonical base64, without padding");
			stanzas.push({args: args, body: body});
		}
	}

	// ---- STREAM

	// (sealed: chunks of 64 KiB, the last one flagged, an empty one for no plaintext)
	static function seal(key:Bytes, data:Bytes):Bytes {
		var out = new BytesBuffer(), counter = 0, at = 0;
		do {
			var n = data.length - at > CHUNK ? CHUNK : data.length - at;
			out.add(ChaCha20Poly1305.seal(key, nonce(counter++, at + n == data.length), data.sub(at, n)));
			at += n;
		} while (at < data.length);
		return out.getBytes();
	}

	// (opened as age's reader streams it, each chunk's plaintext released
	// before the next is read: a full chunk is not the last unless it opens
	// as the last; after the last, nothing)
	static function open(key:Bytes, data:Bytes):Bytes {
		var out = new BytesBuffer(), counter = 0, at = 0, size = CHUNK + ChaCha20Poly1305.TAG;
		function fail(why:String):Dynamic
			throw new AgeError("payload failure", why, out.getBytes());
		while (true) {
			var left = data.length - at;
			if (left == 0) fail("the last STREAM chunk is missing");
			var last = left < size, n = last ? left : size;
			if (last && n == ChaCha20Poly1305.TAG && counter > 0) fail("an empty final STREAM chunk after others");
			var chunk = data.sub(at, n);
			var p = ChaCha20Poly1305.open(key, nonce(counter, last), chunk);
			if (p == null && !last) {
				last = true;
				p = ChaCha20Poly1305.open(key, nonce(counter, true), chunk);
			}
			if (p == null) fail('STREAM chunk $counter does not decrypt');
			out.add(p);
			at += n;
			counter++;
			if (last) {
				if (at < data.length) fail("data after the last STREAM chunk");
				return out.getBytes();
			}
		}
	}

	// (an 11-byte big-endian counter, then the last chunk's flag)
	static function nonce(counter:Int, last:Bool):Bytes {
		if (counter < 0) throw "age: a payload too long";
		var n = ChaCha20Poly1305.zeros(12);
		for (k in 0...4) n.set(10 - k, (counter >>> (8 * k)) & 0xff);
		n.set(11, last ? 1 : 0);
		return n;
	}

	// ---- helpers

	static function wrapKey(shared:Bytes, share:Bytes, pk:Bytes):Bytes {
		var salt = Bytes.alloc(64);
		salt.blit(0, share, 0, 32);
		salt.blit(32, pk, 0, 32);
		return Hkdf.derive(shared, salt, Bytes.ofString("age-encryption.org/v1/X25519"), 32);
	}

	// (a stanza's body in lines of 64 columns, the last one shorter: empty when needed)
	static function wrap(s:String):String {
		var b = new StringBuf(), at = 0;
		while (s.length - at >= 64) {
			b.add(s.substr(at, 64) + "\n");
			at += 64;
		}
		b.add(s.substr(at) + "\n");
		return b.toString();
	}

	public static inline function b64(b:Bytes):String
		return haxe.crypto.Base64.encode(b, false);

	// canonical base64 without padding, else null
	public static function unb64(s:String):Null<Bytes> {
		if (s.length % 4 == 1) return null;
		for (i in 0...s.length) if (B64.indexOf(s.charAt(i)) < 0) return null;
		var b = try haxe.crypto.Base64.decode(s, false) catch (_:Dynamic) return null;
		return b64(b) == s ? b : null;
	}
}

class AgeError {
	public final kind:String;
	public final message:String;
	// (a payload failure's plaintext before the chunk that failed)
	public final partial:Null<Bytes>;

	public function new(kind:String, message:String, ?partial:Bytes) {
		this.kind = kind;
		this.message = message;
		this.partial = partial;
	}

	public function toString():String
		return 'age: $kind: $message';
}
