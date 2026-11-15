package helder.scene.render;

import helder.scene.render.PbrShader;

// The view buffers' prepass of skinned meshes (Skinning's, for ViewBuffers:
// pbr's prepass and skinned; PbrPrepassShader's notes).
final PbrPrepassSkinnedShader = pbr.variant({prepass: true, skinned: true});
