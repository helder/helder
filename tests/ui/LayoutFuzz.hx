// layout-fuzz.mjs's random trees laid out and compared with Chromium's
// boxes, as UiCheck compares its layout cases: LayoutFuzz <dir>
class LayoutFuzz {
	static function main() {
		var dir = Sys.args().length > 0 ? Sys.args()[0] : "bin/ui/fuzz";
		@:privateAccess UiCheck.layouts(dir);
		@:privateAccess {
			Sys.println('LayoutFuzz: ${UiCheck.failed} differ');
			Sys.exit(UiCheck.failed == 0 ? 0 : 1);
		}
	}
}
