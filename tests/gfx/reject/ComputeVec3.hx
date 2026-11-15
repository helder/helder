// A storage buffer's elements have no Vec3.
// expect: ComputeVec3.hx:9: lines 9-11
// expect: the storage points's element is a Vec3: a storage buffer has no Vec3 (16 bytes in std430 and WGSL, 12 in HLSL): pack it into a Vec4
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

final C = compute({
	size: [64],
	main: function(id:ComputeInput, p:{points:RWStorage<Vec3>}) {
		p.points[id.x] = vec3(1);
	}
});

class ComputeVec3 {
	static function main()
		trace(C.code);
}
