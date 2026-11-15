package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostShader;

// the composite with the effects folded in (PostShader's composite, effects;
// with FXAA): PostFx's, a module of its own (linked with the first effect).
final CompositeFxShader = composite.variant({effects: true});
final CompositeFxFxaaShader = composite.variant({effects: true, fxaa: true});
