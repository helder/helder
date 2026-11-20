package helder.pack.ios;

#if macro
import haxe.macro.Context;

// An iOS build's check (helder.cli.Ios: `--macro
// helder.pack.ios.Usage.check("camera,photos")`, the usage strings
// helder.json gives): a permission the program asks for (helder.pack.Uses)
// without its usage string is an error at the call, as iOS would end the
// app there.
class Usage {
	public static function check(given:String) {
		var have = given == "" ? [] : given.split(",");
		haxe.macro.Compiler.define("helder.ios.usage", given == "" ? "-" : given);
		Context.onGenerate(types -> {
			var used = helder.pack.Uses.of(types).permissions;
			for (p in Bundle.missingUsage([for (k in used.keys()) k], have))
				Context.reportError('iOS needs to be told why the app asks for $p: helder.json\'s targets.ios.usage.$p (Info.plist\'s ${Bundle.usageKey(p)})',
					used.get(p));
		});
	}
}
#end
