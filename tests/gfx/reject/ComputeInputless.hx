// A compute function takes the invocation's ids first, and returns nothing.
// expect: the compute function takes the invocation's ids first (id:ComputeInput)
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

final C = compute({
	size: [64],
	main: function(i:Int, p:{data:RWStorage<Int>}) {
		p.data[i] = 1;
	}
});

class ComputeInputless {
	static function main()
		trace(C.code);
}
