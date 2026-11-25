// A subgroup operation after a return under an if on the invocation's id: not every invocation reaches it.
// expect: SubgroupNonUniform.hx:15: characters 11-38
// expect: subgroupAdd(): not every invocation of the workgroup reaches it here
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class Count {
	var n:Int;
}

final C = compute({
	size: [64],
	main: function(id:ComputeInput, p:{count:Count, values:Storage<Float>, out:RWStorage<Float>}) {
		if (id.x >= p.count.n) return;
		var s = subgroupAdd(p.values[id.x]);
		p.out[id.x] = s;
	}
});

class SubgroupNonUniform {
	static function main()
		trace(C.code);
}
