package helder.scene.render;

import helder.scene.render.PbrShader;

// the standard material with a baked lightmap at the second uvs (Lightmaps':
// a module of its own, linked with it alone)
final PbrLightmapShader = pbr.gpuVariant({lightmap: true});
