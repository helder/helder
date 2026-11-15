// A storage buffer's length is not known to every back end.
// expect: ComputeLength.hx:10: characters 15-28
// expect: the length of a storage buffer is not known to every back end (Metal's buffers have none): pass the count in a uniform block
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

final C = compute({
	size: [64],
	main: function(id:ComputeInput, p:{data:RWStorage<Int>}) {
		if (id.x >= p.data.length) return;
		p.data[id.x] = 1;
	}
});

class ComputeLength {
	static function main()
		trace(C.code);
}
