package viewer;

#if macro
import haxe.macro.Context;
#end

// The viewer's version, helder.json's ("version": the one helder build
// gives the bundles, CFBundleShortVersionString), read at compile time: the
// about card's and --version's.
class Version {
	#if !macro
	public static final NAME:String = name();
	#end

	static macro function name() {
		var file = haxe.io.Path.join([haxe.io.Path.directory(Context.getPosInfos(Context.currentPos()).file), "..", "..", "helder.json"]);
		Context.registerModuleDependency(Context.getLocalModule(), file);
		var m:Dynamic = try haxe.Json.parse(sys.io.File.getContent(file)) catch (_:Dynamic) null;
		var v:Null<String> = m == null ? null : m.version;
		return macro $v{v ?? "0.0"};
	}
}
