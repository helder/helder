package helder.scene.render;

import helder.scene.render.PbrShader;

// The view buffers' prepass (ViewBuffers): pbr's prepass variants, the
// opaque surfaces' view-space normal (octahedral, two channels),
// roughness and selection group into an RGBA8 target, their depth into a
// Depth32F one; nothing lit. This the plain one (normal-mapped primitives
// too, by their surface's normal); PbrPrepassInstancedShader the
// instanced runs' and sets', PbrPrepassSkinnedShader the skinned ones'
// (Skinning's): modules of their own, linked only where they are drawn.
final PbrPrepassShader = pbr.variant({prepass: true});
