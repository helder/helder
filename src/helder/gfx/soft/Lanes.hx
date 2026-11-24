package helder.gfx.soft;

// ShaderMath's builtins over lanes (LaneBuild.builtins: VecBuild's
// formulas), what a shader's SIMD form calls
@:build(helder.gfx.soft.LaneBuild.builtins())
class Lanes {}
