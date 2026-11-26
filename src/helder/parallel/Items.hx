package helder.parallel;

// n values of T outside the GC heap, in the GPU's storage layout (std430):
// what each, map and the reductions read and write from any thread, and,
// in the next part, a GPU buffer kept beside them. T is Int, Float, Vec2,
// Vec4, Mat4, or a struct of those (a @:structInit class, a typedef of an
// anonymous structure): Bool and Vec3 have no storage layout (pack a Vec3
// in a Vec4).
//
//   var heights = new Items<Float>(w * h);      // zeros
//   heights[i] = 1.5;                           // on the CPU, checked
//   var ps = Items.of([for (_ in 0...n) {pos: vec4(0), vel: vec4(0)}]);
//   heights.dispose();                          // the memory freed now
//
// dispose() frees it; one never disposed is freed once collected (said in
// debug builds), so that dispose() is for memory you want back now. A
// disposed Items throws where it is read. Each element type is a type of
// its own (helder.parallel.gen.Items_*, made by ItemsMacro).
@:genericBuild(helder.parallel.ItemsMacro.build())
class Items<T> {}
