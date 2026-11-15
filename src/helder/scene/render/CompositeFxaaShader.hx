package helder.scene.render;

import helder.scene.render.PostShader;

// the composite with FXAA (PostShader's composite, fxaa: post.antialias
// Fxaa), a module of its own: linked by a program that sets antialias
final CompositeFxaaShader = composite.gpuVariant({fxaa: true});
