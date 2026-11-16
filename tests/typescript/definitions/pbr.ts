// helder/scene's pbr (src/helder/scene/pbr.ts) is PbrShader.hx's in
// TypeScript: its variants (the renderer's five, the prepass' three) print the same text in
// every language as Haxe's (Pbr.hx), with their layouts, blocks and
// textures. (A literal below 1e-4 is printed by each runtime's Std.string:
// Haxe's macros write 1e-06 where helder's compiler writes 0.000001, so
// Pbr.hx writes it as this does.)
import {pbr, physicalDirect, physicalIndirect, physicalMetalness, physicalRoughness, physicalEmissive} from "helder/scene";
import {print} from "./print";

print(pbr.variant());
print(pbr.variant({normalMap: true}));
print(pbr.variant({skinned: true}));
print(pbr.variant({instanced: true}));
print(pbr.variant({instanced: true, normalMap: true}));
// (the view buffers' prepass: plain, instanced, skinned)
print(pbr.variant({prepass: true}));
print(pbr.variant({prepass: true, instanced: true}));
print(pbr.variant({prepass: true, skinned: true}));
// (Probes': the draw's light and reflection probes, plain and instanced)
print(pbr.variant({probes: true}));
print(pbr.variant({instanced: true, probes: true}));
// (AreaLights': area lights by LTC, alone and with probes)
print(pbr.variant({area: true}));
print(pbr.variant({instanced: true, area: true, probes: true}));
// (the physical material's, PhysicalShader's: every glTF extension, normal mapped; sheen alone)
const physical = pbr.with({direct: physicalDirect, indirect: physicalIndirect, metalness: physicalMetalness, roughness: physicalRoughness, emissive: physicalEmissive});
print(physical.variant({sheen: true, specular: true, clearcoat: true, transmission: true, iridescence: true, anisotropy: true, uvSets: true, normalMap: true}));
print(pbr.with({direct: physicalDirect, indirect: physicalIndirect}).variant({sheen: true}));
