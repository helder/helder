// A storage buffer is read and written in the compute function itself, not passed on.
// expect: ComputeHelper.hx:8: lines 8-9
// expect: b: a Storage<Int> is a parameter of a compute stage (its object of parameters), read and written there
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// (a helper can take no storage buffer)
function first(b:Storage<Int>):Int
	return b[0];

final C = compute({
	size: [64],
	main: function(id:ComputeInput, p:{src:Storage<Int>, dst:RWStorage<Int>}) {
		p.dst[id.x] = first(p.src);
	}
});

class ComputeHelper {
	static function main()
		trace(C.code);
}
