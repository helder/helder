package helder.pack.ios;

#if macro
import haxe.macro.Context;

// An iOS build's check (helder.cli.Ios: `--macro
// helder.pack.ios.Usage.check("camera,photos")`, the usage strings
// helder.json gives): a permission the program asks for (helder.pack.Uses)
// without its usage string is an error at the call, as iOS would end the
// app there. The Info.plist keys the program's classes need by use
// (Uses' plist) are set in the bundle's Info.plist before it is linked
// and signed (-D hxmc.codesign-info-plist, CodeResources' hash of it).
class Usage {
	public static function check(given:String) {
		var have = given == "" ? [] : given.split(",");
		haxe.macro.Compiler.define("helder.ios.usage", given == "" ? "-" : given);
		Context.onGenerate(types -> {
			var uses = helder.pack.Uses.of(types);
			var used = uses.permissions.copy();
			for (k => p in uses.usage) if (!used.exists(k)) used.set(k, p);
			for (p in Bundle.missingUsage([for (k in used.keys()) k], have))
				Context.reportError('iOS needs to be told why the app asks for $p: helder.json\'s targets.ios.usage.$p (Info.plist\'s ${Bundle.usageKey(p)})',
					used.get(p));
			if (uses.plist.length > 0 && Context.defined("hxmc.codesign-info-plist"))
				Bundle.addKeys(Context.definedValue("hxmc.codesign-info-plist"), Context.definedValue("hxmc.codesign-resources"), uses.plist);
		});
	}
}
#end
