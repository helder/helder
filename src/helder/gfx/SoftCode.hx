package helder.gfx;

// A stage's form for the CPU back end (helder.gfx.soft; -D helder.soft builds
// only: helder.gfx.shader.Soft): its entry, a GC-free callback of the back
// end's context, by its address, and how many components its varyings have
// after the position; a compute stage's memory
typedef SoftCode = {
	entry:hxmc.I64,
	varyings:Int,
	// (a compute stage's) its workgroup memory's bytes, and its phases'
	// frame's for each call (4 invocations; 0: no barrier)
	?workgroup:Int,
	?frame:Int
}
