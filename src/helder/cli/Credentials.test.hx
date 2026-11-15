package helder.cli;

import haxe.io.Bytes;
import helder.cli.Options.Usage;
import helder.pack.age.Age;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The credentials store (Credentials): its layout, the account's keys
// falling back to default and the app's signing material not, a missing or
// wrong secret key; then each place that reads it, after what the
// environment and helder.json give (Android.releaseSigner, Ios.signing,
// Publish.serviceAccount, Publish.ascKeyText); and its command line.
function tests() {
	final root = "bin/test/credentials";
	final signing = "tests/pack/signing";
	final key = Age.generate();

	function put(platform:String, app:String, file:String, data:Bytes) {
		var dir = '$root/credentials/$platform/$app';
		TestCommand.mkdirs(dir);
		File.saveBytes('$dir/$file.age', Age.encrypt(data, [Age.recipientOf(key)]));
	}
	function pem(...names:String):String
		return [for (n in names) File.getContent('$signing/$n')].join("");

	var made = false;
	function store() {
		if (made) return;
		made = true;
		if (FileSystem.exists('$root/credentials')) clear('$root/credentials');
		TestCommand.mkdirs('$root/credentials');
		File.saveContent('$root/credentials/recipients.txt', '# test\n${Age.recipientOf(key)}\n');
		put("ios", "default", "asc-api-key.json", Bytes.ofString(haxe.Json.stringify({key_id: "DEFAULT", issuer_id: "team", private_key: pem("key-ec.pem")})));
		put("ios", "org.own", "asc-api-key.json", Bytes.ofString(haxe.Json.stringify({key_id: "OWN", issuer_id: "team", private_key: pem("key-ec.pem")})));
		put("ios", "org.helder.packcheck", "identity.pem", Bytes.ofString(pem("cert.pem", "key.pem")));
		put("ios", "org.helder.packcheck", "profile.mobileprovision", File.getBytes('$signing/test.mobileprovision'));
		// (default's signing material: never read for another app)
		put("ios", "default", "identity.pem", Bytes.ofString(pem("cert.pem", "key.pem")));
		put("android", "default", "service-account.json", Bytes.ofString('{"client_email": "publisher@example", "private_key": "x"}'));
		put("android", "org.helder.packcheck", "upload-identity.pem", Bytes.ofString(pem("cert.pem", "key.pem")));
	}

	test("an entry: the app's, else default's for the account's keys; the app's alone for signing", () -> {
		store();
		var s = Credentials.of(root, key);
		var asc = (id:String) -> haxe.Json.parse(s("ios", id, "asc-api-key").data.toString()).key_id;
		equals(asc("org.own"), "OWN");
		equals(asc("org.other"), "DEFAULT");
		equals(s("ios", "org.own", "asc-api-key").label, '$root/credentials/ios/org.own/asc-api-key.json.age');
		equals(s("ios", "org.other", "identity"), null);
		equals(s("android", "org.other", "upload-identity"), null);
		equals(s("android", "org.other", "service-account").label, '$root/credentials/android/default/service-account.json.age');
		equals(s("ios", "org.helder.packcheck", "profile").data.compare(File.getBytes('$signing/test.mobileprovision')), 0);
		equals(s("ios", null, "asc-api-key"), null);
		throws(() -> s("ios", "org.own", "keystore"));
	});

	test("no store, no key (a warning, nothing read), a wrong key (an error)", () -> {
		store();
		equals(Credentials.of("bin/test/nowhere", key)("ios", "org.own", "asc-api-key"), null);
		equals(Credentials.of(root, "")("ios", "org.own", "asc-api-key"), null);
		var err = Std.string(throws(() -> Credentials.of(root, Age.generate())("ios", "org.own", "asc-api-key")));
		assert(err.endsWith("asc-api-key.json.age: HELDER_CREDENTIALS_KEY does not open it (another store's key?)"), err);
		var err = Std.string(throws(() -> Credentials.of(root, "AGE-SECRET-KEY-1NOPE")("ios", "org.own", "asc-api-key")));
		assert(err.startsWith("HELDER_CREDENTIALS_KEY: not an age secret key"), err);
	});

	test("Android's upload key: the environment's, helder.json's, then the store's", () -> {
		store();
		var s = Credentials.of(root, key);
		var cert = (sig:helder.pack.android.Apk.Signer) -> sig == null ? null : sig.cert.toHex();
		var stored = cert(Android.releaseSigner(null, root, _ -> null, "org.helder.packcheck", s));
		var rsa = helder.pack.apple.Identity.fromPem(pem("cert.pem"), pem("key.pem")).leaf.der.toHex();
		equals(stored, rsa);
		equals(Android.releaseSigner(null, root, _ -> null, "org.other", s), null);
		equals(Android.releaseSigner(null, root, _ -> null, null, s), null);
		var env = ["HELDER_ANDROID_UPLOAD_IDENTITY" => pem("cert-ec.pem", "key-ec.pem")];
		var ec = helder.pack.apple.Identity.fromPem(pem("cert-ec.pem"), pem("key-ec.pem")).leaf.der.toHex();
		equals(cert(Android.releaseSigner(null, root, k -> env.get(k), "org.helder.packcheck", s)), ec);
		// (helder.json's paths: from the project's directory, root)
		var cfg = {android: {signing: {certificate: '../../../$signing/cert-ec.pem', key: '../../../$signing/key-ec.pem'}}};
		equals(cert(Android.releaseSigner(cfg, root, _ -> null, "org.helder.packcheck", s)), ec);
		// (one half given: the store does not make up the other)
		var half = ["HELDER_ANDROID_SIGNING_KEY" => pem("key-ec.pem")];
		assert(Std.string(throws(() -> Android.releaseSigner(null, root, k -> half.get(k), "org.helder.packcheck", s))).startsWith("release signing takes a certificate and its key"));
	});

	test("iOS's identity and profile: the environment's first, the store's for what is not given", () -> {
		store();
		var s = Credentials.of(root, key);
		var o = App.ios("x", {id: "org.helder.packcheck"});
		var r = Ios.signing(o, root, _ -> null, s);
		equals(r.identity.leaf.commonName, helder.pack.apple.Identity.fromPem(pem("cert.pem"), pem("key.pem")).leaf.commonName);
		equals(r.profile.der.compare(File.getBytes('$signing/test.mobileprovision')), 0);
		equals(Ios.signing(App.ios("x", {id: "org.other"}), root, _ -> null, s), null);
		var env = ["HELDER_IOS_IDENTITY" => pem("cert-ec.pem", "key-ec.pem")];
		var r = Ios.signing(o, root, k -> env.get(k), s);
		equals(r.identity.key.ec != null, true);
		// (the profile still the store's: not given)
		assert(r.profile != null);
	});

	test("the store's service account and App Store Connect key, after the environment's", () -> {
		store();
		var s = Credentials.of(root, key);
		var e = Entry.resolve("tests/pack/project");
		var none = (n:String) -> Sys.getEnv(n) == null || Sys.getEnv(n) == "";
		if (["HELDER_PLAY_ACCESS_TOKEN", "GOOGLE_OAUTH_ACCESS_TOKEN", "HELDER_PLAY_SERVICE_ACCOUNT", "GOOGLE_APPLICATION_CREDENTIALS"].filter(none).length == 4)
			equals(Publish.serviceAccount(e, s).client_email, "publisher@example");
		if (["HELDER_ASC_API_KEY", "HELDER_ASC_KEY_ID", "HELDER_ASC_ISSUER_ID", "HELDER_ASC_KEY"].filter(none).length == 4) {
			var k = Publish.ascKeyText(e, s);
			equals([k.id, k.issuer], ["DEFAULT", "team"]);
			assert(k.pem.indexOf("PRIVATE KEY-----") > 0);
		}
	});

	test("helder credentials' command line: init, add, list, its mistakes", () -> {
		store();
		final usage = (f:() -> Void) -> {
			var e = throws(f);
			return e is Usage ? (e : Usage).message : 'not a Usage: $e';
		};
		final parse = (args:Array<String>) -> Options.parse("credentials", args, _ -> true);
		equals(parse([]).positionals, []);
		equals(parse(["add", "ios", "identity", "id.pem", "--app", "org.x"]).value("app"), "org.x");
		equals(parse(["list", "examples/todo"]).positionals, ["list", "examples/todo"]);
		equals(usage(() -> parse(["show"])), "helder credentials: show: init, add or list (helder credentials --help)");
		equals(usage(() -> parse(["add", "ios", "identity"])), "helder credentials: add <ios|android> <kind> <file> [entry] (helder credentials --help)");
		equals(usage(() -> parse(["add", "web", "identity", "f"])), "helder credentials: add web: ios or android (helder credentials --help)");
		equals(usage(() -> parse(["list", "--app", "x"])), "helder credentials: --app: with add (helder credentials --help)");
		assert(Options.helpText().indexOf("\n  credentials ") >= 0);
		assert(Options.helpText("credentials").indexOf("--app <id>") >= 0);
		throws(() -> Credentials.kind("ios", "keystore"));
	});

	test("helder credentials add: the file checked, encrypted to the store's keys, under the app's id", () -> {
		store();
		File.saveContent('$root/identity.pem', pem("cert-ec.pem", "key-ec.pem"));
		var run = (args:Array<String>) -> Credentials.run(Options.parse("credentials", args, _ -> true));
		equals(run(["add", "ios", "identity", '$root/identity.pem', root, "--app", "org.added"]), 0);
		var f = '$root/credentials/ios/org.added/identity.pem.age';
		equals(Age.decrypt(File.getBytes(f), [key]).toString(), pem("cert-ec.pem", "key-ec.pem"));
		// (the account's keys: default's unless --app; signing material: never default's)
		File.saveContent('$root/asc.json', '{"key_id": "K", "issuer_id": "I", "private_key": "P"}');
		equals(run(["add", "ios", "asc-api-key", '$root/asc.json', root, "--app", "default"]), 0);
		equals(run(["add", "ios", "identity", '$root/identity.pem', root, "--app", "default"]), 1);
		equals(run(["add", "android", "service-account", '$root/asc.json', root, "--app", "org.x"]), 1);
		equals(run(["add", "ios", "profile", '$root/asc.json', root, "--app", "org.x"]), 1);
		assert(!FileSystem.exists('$root/credentials/ios/org.x'));
	});
}

private function clear(dir:String) {
	for (f in FileSystem.readDirectory(dir)) {
		var p = '$dir/$f';
		if (FileSystem.isDirectory(p)) {
			clear(p);
			FileSystem.deleteDirectory(p);
		} else FileSystem.deleteFile(p);
	}
}
