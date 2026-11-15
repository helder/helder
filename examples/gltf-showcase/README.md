# glTF sample models

Khronos' [glTF sample models](https://github.com/KhronosGroup/glTF-Sample-Assets),
the scenes other engines demo with, in helder.scene: DamagedHelmet,
FlightHelmet, SciFiHelmet and MetalRoughSpheres, and the tests of the glTF
extensions helder reads: KHR_texture_transform, KHR_materials_emissive_strength,
_clearcoat, _transmission, _volume, _ior, _specular, _sheen, _iridescence and
_anisotropy (SheenChair, IridescenceLamp, AnisotropyBarnLamp, IORTestGrid,
SpecularTest, DragonAttenuation, the Compare* models, AttenuationTest,
TransmissionRoughnessTest). A model picker and an environment picker over a
`<Scene hdr>` with `<OrbitControls>`; prefiltered image-based light
(`Environment.prefiltered`), bloom and ACES (`PostProcess`); the models,
loaded at run time, drawn by `Physical` (every extension's shader) with
`Transmission` (the opaque frame behind see-through surfaces).

```sh
node examples/gltf-showcase/fetch.mjs                     # the models, into models/ (91 MB, git-ignored)
bun run helder examples/gltf-showcase/GltfShowcase.hx     # natively
bun run helder examples/gltf-showcase/GltfShowcase.hx --target web
```

- `fetch.mjs` downloads each model from glTF-Sample-Assets at a pinned
  commit, a `.gltf`'s buffers and images packed into one `.glb` (what
  `Model.load` reads), with its `metadata.json` (its licences and credits) and
  the sample viewer's reference render beside it. The site's build runs it
  (`// data: models`) and serves the models beside the module.
- `envbake.py` filters a Radiance `.hdr` panorama into the atlas
  `Environment.prefiltered` reads (GGX rows by roughness and the irradiance,
  256 wide), scaled to fit 8 bits (the scale is the environment's
  intensity). `environments/` holds three, from Poly Haven's CC0 panoramas
  (studio_small_09, venice_sunset, kloofendal_48d_partly_cloudy_puresky).
- `Showcase.hx` is the scene (the models, the environments, the camera
  fitted to the bounds), shared by the example and by `Shots.hx`, which
  draws each model headless for the comparison below.
- The program prints `stats: {...}` lines (the first frame, the download, the
  GPU's texture bytes, frame times' p50 and p99); `site/numbers.mjs` reads
  them for the site's page of this example.

## Against the sample viewer

Each model's reference render (its `screenshot/` image in glTF-Sample-Assets,
the Khronos sample viewer's, at its own size, camera and environment) beside
helder's frame (`Shots.hx`: the file's camera where it has one, else from
the front; the studio environment lighting it, not drawn; HDR, bloom, ACES;
Mesa's llvmpipe):

![The sample viewer's renders beside helder's](comparison.jpg)

```sh
helder build examples/gltf-showcase/Shots.hx -o bin/shots
LIBGL_ALWAYS_SOFTWARE=1 bin/shots examples/gltf-showcase bin/shots-out
```

| Model | | |
| --- | --- | --- |
| DamagedHelmet | correct | metallic-roughness, occlusion, emissive and normal maps; the pose and environment differ |
| FlightHelmet | correct | six materials, normal maps; the lenses' transmission tinted (below) |
| SciFiHelmet | correct | |
| MetalRoughSpheres | correct | metal and roughness by the texture's rows and columns |
| TextureTransformTest | correct | offset, rotation and scale: every check mark where the test puts it, no cross |
| EmissiveStrengthTest | correct | brighter left to right (strengths 1 to 16); the reference's darker grid and stronger glow are its exposure and bloom |
| ClearCoatTest | correct | the coat's factor, roughness and their maps (the partial coat's stripes), its own normal map (the last row) |
| TransmissionTest | correct | the checker refracted through each ball (Transmission's copy of the frame), blurred by roughness, transmissionTexture's stripes; the opacity column cut out |

The other material extensions, each model's reference render beside
helder's (Shots.hx, the same way; `comparison-extensions.jpg`):

![The sample viewer's renders beside helder's, the material extensions](comparison-extensions.jpg)

| Model | | |
| --- | --- | --- |
| SheenChair | correct | the velvet's sheen (KHR_materials_sheen), its tufts (the normal map at its own transform) and the occlusion on TEXCOORD_1 (`uvSets`) |
| IridescenceLamp | mostly | the globe's thin film and its glass refracting the stand; the film fainter than the reference's, whose environment is brighter around it |
| AnisotropyBarnLamp | correct | the brushed copper's stretched highlights (the anisotropy map's directions), the clear coat with its own normal map, the bulb's glass |
| IORTestGrid | correct | each row's ior: the reflections stronger and the checker bent more from air to diamond |
| SpecularTest | correct | the specular factor and colour, by factors and maps, rows as the reference's |
| DragonAttenuation | correct | the dragon's volume absorbing towards amber, more where it is thicker (its thickness map) |
| CompareSheen, CompareSpecular | correct | the sheen's rim; the darker specular |
| CompareIridescence | correct | the film's colours over the black ball |
| CompareAnisotropy | correct | the disc brushed radially, the ball along its tangents |
| CompareIor, CompareVolume, AttenuationTest | correct | the logo bent by the higher ior; the bowl's water absorbing towards green; the cubes darker with thickness, by factor, map and node scale, and by distance |
| TransmissionRoughnessTest | correct | the grid blurred more with roughness, more with ior (`applyIorToRoughness`) |

The sample viewer differs in how it lights (its own environment and
punctual lights) and in two approximations here: the sheen's albedo is
three.js' fit, not the viewer's lookup tables, and light from punctual
lights through a volume is not added.

alphaMode MASK (TransmissionTest's opacity column) is cut out (`discard()`,
new in gfx's shaders). The 3d lane's goldens `khrtransform` and
`khrclearcoat` (tests/3d) draw TextureTransformTest and ClearCoatTest,
vendored there (CC0, CC BY 4.0).

## Credits

- DamagedHelmet: CC BY 4.0 ctxwing (rebuild and glTF), after theblueturtle_ (CC BY-NC 4.0)
- FlightHelmet: CC0 Gary Hsu
- SciFiHelmet: CC0 Michael Pavlovic, Norbert Nopper
- MetalRoughSpheres, EmissiveStrengthTest, ClearCoatTest: CC BY 4.0 Ed Mackey
- TextureTransformTest: CC0 Microsoft
- TransmissionTest: CC0 Adobe
- SheenChair, IORTestGrid: CC0 Eric Chadwick; IridescenceLamp, AnisotropyBarnLamp: CC BY 4.0 Eric Chadwick
- SpecularTest, AttenuationTest, TransmissionRoughnessTest: CC BY 4.0 Ed Mackey
- DragonAttenuation: Stanford Graphics (the dragon), Morgan McGuire's Computer Graphics Archive, CC0 Adobe
- CompareSheen, CompareIridescence, CompareAnisotropy, CompareSpecular, CompareIor, CompareVolume: CC0 Eric Chadwick and DGG (the glTF logo a Khronos trademark)
- The reference renders in `comparison.jpg`: from glTF-Sample-Assets, under the models' licences
- Panoramas: Poly Haven, CC0
