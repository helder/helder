package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostShader;

// the composite with the effects folded in and SMAA's blending (PostShader's
// composite, effects and smaa: post.smaa: Smaa), a module of its own:
// linked by a program that sets it (SmaaPass.install)
final CompositeFxSmaaShader = composite.gpuVariant({effects: true, smaa: true});
