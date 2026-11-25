// barrier() where not every invocation of the workgroup reaches it: under an if on its id.
// expect: WorkgroupBarrierIf.hx:13: characters 4-13
// expect: barrier(): not every invocation of the workgroup reaches it here (under an if or a loop on values that differ between invocations, or after a return under one): it needs uniform control flow, as WGSL does
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

final C = compute({
	size: [64],
	main: function(id:ComputeInput, p:{out:RWStorage<Float>}, w:{part:Workgroup<Float>}) {
		w.part[id.localIndex] = 1;
		if (id.localIndex < 32) {
			w.part[id.localIndex] = 2;
			barrier();
		}
		p.out[id.x] = w.part[63 - id.localIndex];
	}
});

class WorkgroupBarrierIf {
	static function main()
		trace(C.code);
}
