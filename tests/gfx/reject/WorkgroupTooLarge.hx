// A stage's workgroup memory is 16 KB at most.
// expect: WorkgroupTooLarge.hx:10: lines 10-13
// expect: workgroup memory: 17408 bytes, more than 16384 (16 KB, WebGPU's and GL ES 3.1's limit)
import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

final C = compute({
	size: [64],
	main: function(id:ComputeInput, p:{out:RWStorage<Vec4>}, w:{@:length(1024) var tiles:Workgroup<Vec4>; var more:Workgroup<Vec4>;}) {
		w.tiles[id.localIndex] = w.more[id.localIndex];
		p.out[id.x] = w.tiles[id.localIndex];
	}
});

class WorkgroupTooLarge {
	static function main()
		trace(C.code);
}
