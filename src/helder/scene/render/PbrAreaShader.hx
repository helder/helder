package helder.scene.render;

import helder.scene.render.PbrShader;

// the standard material with area lights by linearly transformed cosines
// (AreaLights': a module of its own, linked with it alone), plain and
// instanced, and with Probes' probes too
final PbrAreaShader = pbr.gpuVariant({area: true});

final PbrInstancedAreaShader = pbr.gpuVariant({instanced: true, area: true});

final PbrAreaProbesShader = pbr.gpuVariant({area: true, probes: true});

final PbrInstancedAreaProbesShader = pbr.gpuVariant({instanced: true, area: true, probes: true});
