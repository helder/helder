// helder/scene's shading models (src/helder/scene/shading.ts) are
// helder.scene.render.shading's in TypeScript: their variants print the
// same text in every language as Haxe's (Shading.hx), with their layouts,
// blocks and textures: pbr with its direct and indirect slots replaced
// (lambert, toon, phong), unlit and its colour slot replaced (matcap,
// normals, depth), plain and instanced.
import {lambert, toon, phong, unlit, matcap, normals, depth} from "helder/scene";
import {print} from "./print";

print(lambert.variant());
print(toon.variant());
print(toon.variant({instanced: true}));
print(phong.variant());
print(unlit.variant());
print(unlit.variant({instanced: true}));
print(unlit.variant({skinned: true}));
print(matcap.variant());
print(normals.variant());
print(depth.variant());
