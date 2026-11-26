// helder dev's arguments under the dev host (tests/os/dev/dev-args.mjs): each
// build prints its version and Sys.args(), the host's arguments after the
// library's path, then hands over to the next library HXMC_DEV_NEXT lists
// (no window: helder.dev.Hosted.handOver, as Hot does at a reload)
class DevArgsCheck {
	static function main() {
		var version = haxe.macro.Compiler.getDefine("devargs_version");
		Sys.println('DevArgsCheck: v$version ${Sys.args().join("|")}');
		Sys.stdout().flush();
		var next = Sys.getEnv("HXMC_DEV_NEXT");
		if (next == null || next == "") return;
		var k = next.indexOf(";");
		Sys.putEnv("HXMC_DEV_NEXT", k < 0 ? "" : next.substr(k + 1));
		helder.dev.Hosted.handOver(k < 0 ? next : next.substr(0, k));
	}
}
