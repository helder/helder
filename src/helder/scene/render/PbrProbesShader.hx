package helder.scene.render;

import helder.scene.render.PbrShader;

// the standard material lit by the draw's probes (Probes: its light probes'
// irradiance, its reflection probes' light; a module of its own, linked
// with Probes alone), plain and instanced
final PbrProbesShader = pbr.gpuVariant({probes: true});

final PbrInstancedProbesShader = pbr.gpuVariant({instanced: true, probes: true});
