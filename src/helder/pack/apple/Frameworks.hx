package helder.pack.apple;

import haxe.io.Bytes;
import haxe.io.Path;
import helder.pack.ios.Bundle;
import helder.pack.ios.Plist;

// The libraries of helder's that a program's classes need by use
// (@:helder.apple.framework("<name>"): helder.pack.Uses), prebuilt in
// helder's src/ (HelderStore: helder.store's StoreKit 2,
// src/helder/store/apple/<platform>/HelderStore, build.sh's), put into the
// app bundle and signed by helder (CodeSign: ad hoc, else by the app's
// identity), so the app's own seal binds them:
// - iOS: Frameworks/<name>.framework/ (the App Store takes no loose
//   library): its binary, Info.plist and _CodeSignature/CodeResources,
//   hashed as the app's other files are; put in by the build's macro
//   (check: before the link signs the app), signed again for distribution
//   (helder.cli.Ios);
// - macOS: Contents/Frameworks/<name>.dylib, nested code that the app's
//   seal names by its slices' cdhashes (helder.cli.Mac; a framework's
//   versioned layout needs links, which not every host writes).
class Frameworks {
	static final KNOWN = ["HelderStore" => {id: "build.helder.store", dir: "helder/store/apple"}];

	#if macro
	// (helder.cli.Ios and Mac: --macro helder.pack.apple.Frameworks.check();
	// a TypeScript program's are what it links, helder.typescript.Uses')
	public static function check()
		if (!haxe.macro.Context.defined("helder.typescript"))
			haxe.macro.Context.onGenerate(types -> used(helder.pack.Uses.of(types).frameworks,
				n -> haxe.macro.Context.defined(n) ? haxe.macro.Context.definedValue(n) : null));
	#end

	// those a program uses (helder.typescript.Uses: a TypeScript program's):
	// their names written to -D helder.apple.frameworks' file; an iOS
	// bundle's (-D hxmc.codesign-resources) put in it, ad hoc, and hashed
	// in its CodeResources (-D helder.src: helder's src/)
	public static function used(names:Array<String>, define:String->Null<String>) {
		var list = define("helder.apple.frameworks");
		if (list != null) sys.io.File.saveContent(list, names.join("\n"));
		var resources = define("hxmc.codesign-resources"), src = define("helder.src");
		if (names.length == 0 || resources == null || src == null) return;
		var app = Path.directory(Path.directory(resources)), platform = define("hxmc.target") ?? "ios-arm64";
		var files = new Map<String, Bytes>();
		for (n in names)
			for (f in ios(n, binary(src, n, platform), platform)) {
				sys.FileSystem.createDirectory(Path.directory('$app/${f.path}'));
				sys.io.File.saveBytes('$app/${f.path}', f.data);
				files.set(f.path, f.data);
			}
		Bundle.addFiles(resources, files);
	}

	// platform: ios-arm64, ios-sim-arm64, macos (both slices)
	public static function binary(src:String, name:String, platform:String):Bytes {
		var k = KNOWN.get(name);
		if (k == null) throw 'no library $name of helder\'s';
		return sys.io.File.getBytes('$src/${k.dir}/$platform/$name');
	}

	// the names of those in an iOS bundle already
	public static function inIos(app:String):Array<String> {
		var dir = '$app/Frameworks';
		if (!sys.FileSystem.exists(dir)) return [];
		var out = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".framework") && KNOWN.exists(f.substr(0, f.length - 10))) f.substr(0, f.length - 10)];
		out.sort(Reflect.compare);
		return out;
	}

	// iOS's framework, its files' paths from the app's directory; sign:
	// the app's identity and team (null: ad hoc); extra: Info.plist's keys
	// of the toolchain (a device's, as the app's)
	public static function ios(name:String, bin:Bytes, platform:String, ?sign:{identity:Identity, team:String},
			?extra:Map<String, PValue>):Array<{path:String, data:Bytes}> {
		var sim = platform == "ios-sim-arm64";
		var keys = [
			"CFBundleDevelopmentRegion" => PString("en"),
			"CFBundleExecutable" => PString(name),
			"CFBundleIdentifier" => PString(KNOWN.get(name).id),
			"CFBundleInfoDictionaryVersion" => PString("6.0"),
			"CFBundleName" => PString(name),
			"CFBundlePackageType" => PString("FMWK"),
			"CFBundleShortVersionString" => PString("1.0"),
			"CFBundleSupportedPlatforms" => PArray([PString(sim ? "iPhoneSimulator" : "iPhoneOS")]),
			"CFBundleVersion" => PString("1"),
			"DTPlatformName" => PString(sim ? "iphonesimulator" : "iphoneos"),
			"MinimumOSVersion" => PString("15.0")
		];
		if (extra != null) for (k => v in extra) keys.set(k, v);
		var info = Plist.xml(PDict(keys)), seal = Bundle.codeResources(["Info.plist" => info]);
		var signed = CodeSign.sign(bin, {
			identifier: KNOWN.get(name).id,
			identity: sign?.identity,
			team: sign?.team,
			infoPlist: info,
			resources: seal
		});
		var dir = 'Frameworks/$name.framework';
		return [
			{path: '$dir/$name', data: signed},
			{path: '$dir/Info.plist', data: info},
			{path: '$dir/_CodeSignature/CodeResources', data: seal}
		];
	}

	// macOS's library (its path from Contents/), each slice signed (runtime,
	// timestamp: Developer ID's, as the app's), and the seal's entry of it:
	// the first slice's cdhash, a requirement any slice's satisfies
	public static function mac(name:String, bin:Bytes, identity:Null<Identity>, ?runtime:Int, ?timestamp:Bytes->Bytes):{path:String, data:Bytes,
		cdhash:Bytes, requirement:String} {
		var slices = [
			for (s in Fat.slices(bin))
				CodeSign.sign(s, {identifier: KNOWN.get(name).id, identity: identity, runtime: runtime, timestamp: timestamp})
		];
		var hashes = [for (s in slices) CodeSign.cdhash(s).sub(0, 20)];
		return {
			path: 'Frameworks/$name.dylib',
			data: Fat.make(slices),
			cdhash: hashes[0],
			requirement: [for (h in hashes) 'cdhash H"${h.toHex()}"'].join(" or ")
		};
	}
}
