package helder.gfx;

enum abstract Stage(Int) {
	var Vertex;
	var Fragment;
	// (Device.has(Compute))
	var Compute;
}
