// Every shader src/helder defines (SoftShaders) in its CPU back end's form
// (-D helder.soft) against its scalar reference, built -D helder.soft.exact
// -D helder.soft.reference (bun run test gfx-soft): RUNS random inputs,
// uniform blocks and textures each, the SIMD form's outputs equal to the
// scalar code's bit for bit (helder.gfx.soft.Check).
class SoftShaderTest {
	static inline var RUNS = 40;

	static function main() {
		var all = SoftShaders.all(), failed = 0, checked = 0;
		for (s in all) {
			if (s.shader == null) continue;
			checked++;
			for (seed in 0...RUNS) {
				var e = s.shader.softCheck(seed);
				if (e == null) continue;
				Sys.println('SoftShaderTest: FAIL: ${s.name}: $e (seed $seed)');
				failed++;
				break;
			}
		}
		Sys.println('SoftShaderTest: ${checked - failed} of $checked shaders equal to their scalar code, $RUNS runs each');
		Sys.exit(failed == 0 && checked > 0 ? 0 : 1);
	}
}
