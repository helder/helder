# Models and materials

Load glTF models with their names checked when you build: a typo in a node or animation name is a compile error, not a crash. Materials are glTF's physically based ones, every extension included, and when you need your own look you replace one slot of the standard shader instead of writing a shader from scratch.

<Example id="scene-materials"/>

```haxe
var hero = Model.of('models/hero.glb');      // read and typed when compiling
var root = hero.instantiate(world, device);  // GPU meshes made once, shared
var hand = root.find(hero.nodes.LeftHand);   // LeftHnad: a compile error

// base colour, metallic, roughness
var gold = new Material('gold', new Vec4(1, 0.78, 0.34, 1), 1, 0.2);
MeshRenderer.attach(world.node('ball'), Shapes.sphere(device, gold, 0.5));
```

A material of your own replaces slots of the standard one: here a pulsing emission, in TypeScript.

```ts
const Glow = material(pbr.with({
  emissive: (s: PbrSurface, p: {glow: GlowParams}): Vec3 =>
    p.glow.color.xyz.mul(0.6 + 0.4 * sin(p.glow.time.x * 3 + s.world.x))
}))
Glow.apply(orb, {glow: bytes})
```

## What else

- **Animation:** glTF clips with crossfades, and skinned meshes.
- **Loading:** models packed for run time when you build, loaded in the background, with GPU-compressed textures.
- **Every glTF material extension:** clear coat, sheen, transmission and volume, iridescence, anisotropy, specular, emissive strength, texture transforms.
- **Shading models:** Lambert, toon, Phong, unlit, matcap, normals and depth, as three.js names them.
- **Geometry in code:** boxes, spheres, cylinders, tori, curves, extrusions and text.

<Reference to="scene,asset"/>
