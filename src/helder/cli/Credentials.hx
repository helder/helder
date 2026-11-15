package helder.cli;

import haxe.io.Bytes;
import haxe.io.Path;
import helder.pack.age.Age;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The app's signing and store credentials kept in its own repository,
// encrypted in age's format (helder.pack.age: X25519 recipients), so that
// the repository is their backup and the way a team shares them:
//
//   credentials/recipients.txt                       the public key(s), age1... (committed)
//   credentials/ios/default/asc-api-key.json.age     the App Store Connect API key, the team's
//   credentials/ios/<bundle id>/asc-api-key.json.age  ... one app's own (over default's)
//   credentials/ios/<bundle id>/identity.pem.age     the distribution certificate, its chain, its key
//   credentials/ios/<bundle id>/profile.mobileprovision.age
//   credentials/android/default/service-account.json.age   Play's service account (one app's over it)
//   credentials/android/<package>/upload-identity.pem.age  Play's upload key and certificate
//
// Anyone with a clone adds an entry (encrypting takes the public keys
// alone); reading one takes the secret key, `AGE-SECRET-KEY-1...`, which
// helder never writes: printed once by `helder credentials init`, then
// given as HELDER_CREDENTIALS_KEY (CI's one secret). The account's keys
// (asc-api-key, service-account) fall back from the app's entry to
// `default`; the app's signing material is the app's alone. What the
// environment and helder.json name comes first (Android.releaseSigner,
// Ios.signing, Publish.serviceAccount, Publish.ascKeyText): the store is the
// last place looked. An entry is decrypted in memory and handed on as text
// (each of those reads a value's text as well as a file's path): nothing
// decrypted is written to disk. The files are age's own: `age -d -i key.txt
// credentials/ios/default/asc-api-key.json.age` reads one, `age -R
// credentials/recipients.txt` writes one.
class Credentials {
	public static inline var DIR = "credentials";
	public static inline var RECIPIENTS = "recipients.txt";
	public static inline var KEY = "HELDER_CREDENTIALS_KEY";

	// what an entry holds: its platform, its file's name, whether it is the
	// account's (an app's entry, else default's), the variable it stands in for
	public static final KINDS:Array<Kind> = [
		{name: "asc-api-key", platform: "ios", file: "asc-api-key.json", account: true, env: "HELDER_ASC_API_KEY"},
		{name: "identity", platform: "ios", file: "identity.pem", account: false, env: "HELDER_IOS_IDENTITY"},
		{name: "profile", platform: "ios", file: "profile.mobileprovision", account: false, env: "HELDER_IOS_PROFILE"},
		{name: "service-account", platform: "android", file: "service-account.json", account: true, env: "HELDER_PLAY_SERVICE_ACCOUNT"},
		{name: "upload-identity", platform: "android", file: "upload-identity.pem", account: false, env: "HELDER_ANDROID_UPLOAD_IDENTITY"},
	];

	// (the entries warned about this run: one line each)
	static final warned = new Map<String, Bool>();

	// the store's lookup for a project's directory (key: the secret key,
	// else HELDER_CREDENTIALS_KEY): an entry's label (its path) and its
	// plaintext, null when there is none. An entry there but no key: a
	// warning, null (the build goes on as without it). A key that opens no
	// entry: an error
	public static function of(root:String, ?key:String):Lookup {
		var dir = store(root);
		return (platform, id, name) -> {
			if (id == null || !FileSystem.exists('$dir/$RECIPIENTS')) return null;
			var k = kind(platform, name);
			var path:Null<String> = null;
			for (app in (k.account ? [id, "default"] : [id])) {
				var p = '$dir/$platform/$app/${k.file}.age';
				if (FileSystem.exists(p)) {
					path = p;
					break;
				}
			}
			if (path == null) return null;
			var label = path.replace("\\", "/");
			var secret = key ?? Sys.getEnv(KEY);
			if (secret == null || secret.trim() == "") {
				if (!warned.exists(label)) {
					warned.set(label, true);
					Term.err(Style.status("credentials", Warn, '$label not read: $KEY not set (the store\'s secret key, AGE-SECRET-KEY-1...)'));
				}
				return null;
			}
			return {label: label, data: open(path, secret)};
		};
	}

	// a project's store
	public static function store(root:String):String
		return root == "." || root == "" ? DIR : '${root.replace("\\", "/")}/$DIR';

	// an entry's plaintext (age's file, the secret key)
	public static function open(path:String, secret:String):Bytes {
		var id = try {
			Age.secret(secret);
			secret.trim();
		} catch (err:String) throw '$KEY: $err';
		return try Age.decrypt(File.getBytes(path), [id]) catch (e:AgeError) throw switch e.kind {
			case "no match": '$path: $KEY does not open it (another store\'s key?)';
			case _: '$path: ${e.kind}: ${e.message}';
		}
	}

	// an entry's text as the variable it stands in for takes it (a profile in base64)
	public static function text(k:Kind, data:Bytes):String
		return k.name == "profile" ? haxe.crypto.Base64.encode(data) : data.toString();

	public static function kind(platform:String, name:String):Kind {
		var k = Lambda.find(KINDS, k -> k.platform == platform && k.name == name);
		if (k == null) throw '$platform $name: not a credential (${[for (k in KINDS) '${k.platform} ${k.name}'].join(", ")})';
		return k;
	}

	// ---- helder credentials

	public static function run(o:Options):Int {
		var action = o.positionals[0];
		var entryAt = action == "add" ? 4 : 1;
		var root = try {
			var e = Entry.resolve(o.positionals[entryAt]);
			{root: e.root, e: e};
		} catch (err:Dynamic) {
			if (action == "add" && o.value("app") == null) {
				Term.err(Style.usage('helder credentials: $err'));
				return 2;
			}
			{root: o.positionals[entryAt] ?? ".", e: null};
		}
		var dir = store(root.root);
		try {
			switch action {
				case "init":
					return init(dir);
				case "add":
					return add(dir, root.e, o.positionals[1], o.positionals[2], o.positionals[3], o.value("app"));
				case _:
					return list(dir);
			}
		} catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
		}
	}

	// (recipients.txt made: a new key, printed once; or HELDER_CREDENTIALS_KEY's, nothing printed)
	static function init(dir:String):Int {
		var file = '$dir/$RECIPIENTS';
		if (FileSystem.exists(file)) throw '$file exists: the store is there (helder credentials list)';
		var given = Sys.getEnv(KEY);
		var secret = given != null && given.trim() != "" ? try {
			Age.secret(given);
			given.trim();
		} catch (err:String) throw '$KEY: $err' : Age.generate();
		var recipient = Age.recipientOf(secret);
		TestCommand.mkdirs(dir);
		File.saveContent(file, [
			"# helder credentials: the store's public keys (age's X25519 recipients). Committed:",
			"# anyone with a clone can add an entry (helder credentials add). The secret key",
			"# that reads them is HELDER_CREDENTIALS_KEY, never in the repository.",
			recipient,
			""
		].join("\n"));
		Term.out(Style.status("made", Ok, '$file' + Style.dim(Style.sep() + recipient)));
		if (given != null && given.trim() != "") {
			Term.out(Style.status("key", Info, '$KEY\'s: nothing to keep'));
			return 0;
		}
		Term.out("");
		Term.out(Style.status("secret", Warn, "the store's secret key, shown this once: keep it in a password manager"));
		Term.out("");
		Term.out('  $secret');
		Term.out("");
		Term.out(Style.status("next", Info, 'give it as $KEY (CI: gh secret set $KEY), then helder credentials add ...'));
		return 0;
	}

	static function add(dir:String, e:Null<Entry>, platform:String, name:String, from:String, app:Null<String>):Int {
		var recipients = try Age.recipients(File.getContent('$dir/$RECIPIENTS')) catch (err:String) throw '$dir/$RECIPIENTS: $err' catch (_:Dynamic)
			throw 'no store: $dir/$RECIPIENTS (helder credentials init)';
		if (recipients.length == 0) throw '$dir/$RECIPIENTS: no public key';
		var k = kind(platform, name);
		var id = app ?? (k.account ? "default" : e == null ? null : platform == "ios" ? App.ios(e.name, e.config).id : App.android(e.name, e.config).id);
		if (id == null) throw '${k.platform} ${k.name}: whose? --app <id>';
		if (id == "default" && !k.account) throw '${k.platform} ${k.name} is one app\'s: --app <its id>, not default';
		if (!~/^[A-Za-z0-9._-]+$/.match(id)) throw '--app $id: an app\'s id (com.example.app) or default';
		if (!FileSystem.exists(from) || FileSystem.isDirectory(from)) throw '$from: no such file';
		var data = File.getBytes(from);
		check(k, data, from);
		var path = '$dir/$platform/$id/${k.file}.age';
		var replaced = FileSystem.exists(path);
		TestCommand.mkdirs(Path.directory(path));
		File.saveBytes(path, Age.encrypt(data, recipients));
		Term.out(Style.status(replaced ? "replaced" : "added", Ok, path.replace("\\", "/") + Style.dim(Style.sep() + '${k.env}\'s, for ${recipients.length} key${recipients.length == 1 ? "" : "s"}')));
		Term.out(Style.status("next", Info, 'commit it; keep or delete $from (helder reads the store from now on)'));
		return 0;
	}

	// (a file that is what its kind takes: its mistakes now, not at the next release)
	static function check(k:Kind, data:Bytes, from:String) {
		var s = data.toString();
		switch k.name {
			case "asc-api-key":
				var j:Dynamic = try haxe.Json.parse(s) catch (_:Dynamic) throw '$from: not JSON (asc-api-key.json: "key_id", "issuer_id", "private_key")';
				if ((j.key_id ?? j.keyId) == null || (j.issuer_id ?? j.issuerId) == null || (j.private_key ?? j.privateKey ?? j.key) == null)
					throw '$from: JSON of "key_id", "issuer_id" and "private_key" (helder setup ios writes it)';
			case "service-account":
				var j:Dynamic = try haxe.Json.parse(s) catch (_:Dynamic) throw '$from: not JSON (a service account\'s key)';
				if (j.client_email == null || j.private_key == null) throw '$from: not a service account\'s key (client_email, private_key)';
			case "identity", "upload-identity":
				if (s.indexOf("-----BEGIN CERTIFICATE-----") < 0 || s.indexOf("PRIVATE KEY-----") < 0) throw '$from: one PEM of the certificate and its key (helder setup writes it)';
				try helder.pack.apple.Identity.fromPem(s, s) catch (err:String) throw '$from: $err';
			case "profile":
				if (data.length == 0 || data.get(0) != 0x30) throw '$from: not a provisioning profile (.mobileprovision)';
		}
	}

	static function list(dir:String):Int {
		var file = '$dir/$RECIPIENTS';
		if (!FileSystem.exists(file)) {
			Term.out(Style.status("none", Info, 'no store here ($file: helder credentials init)'));
			return 0;
		}
		var recipients = Age.recipients(File.getContent(file));
		var secret = Sys.getEnv(KEY);
		var has = secret != null && secret.trim() != "";
		var mine = has ? try Age.recipientOf(secret) catch (_:Dynamic) null : null;
		Term.out(Style.status("store", Info, '$dir' + Style.dim(Style.sep() + '${recipients.length} key${recipients.length == 1 ? "" : "s"}'
			+ (has ? (recipients.contains(mine) ? ', $KEY one of them' : ', $KEY not one of them') : ', $KEY not set'))));
		var failed = false;
		for (p in ["ios", "android"]) {
			var pd = '$dir/$p';
			if (!FileSystem.exists(pd)) continue;
			var apps = FileSystem.readDirectory(pd);
			apps.sort(Reflect.compare);
			for (app in apps) {
				var files = FileSystem.isDirectory('$pd/$app') ? FileSystem.readDirectory('$pd/$app') : [];
				files.sort(Reflect.compare);
				for (f in files) {
					var k = Lambda.find(KINDS, k -> k.platform == p && '${k.file}.age' == f);
					var what = k == null ? "not one helder reads" : '${k.name} (${k.env})';
					var state = "";
					if (has && k != null) state = try {
						open('$pd/$app/$f', secret);
						", opens";
					} catch (err:Dynamic) {
						failed = true;
						', ${Std.string(err).split(": ").pop()}';
					}
					Term.out('  ${'$p/$app/$f'.rpad(" ", 52)} $what$state');
				}
			}
		}
		return failed ? 1 : 0;
	}
}

typedef Kind = {name:String, platform:String, file:String, account:Bool, env:String};
typedef Lookup = (platform:String, id:Null<String>, name:String) -> Null<{label:String, data:Bytes}>;
