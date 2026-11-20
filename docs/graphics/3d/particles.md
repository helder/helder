# Particles and instancing

Draw many things in few draw calls. GPU particles are written once when emitted and moved by the GPU from then on, so a million cost the CPU nothing. Instanced meshes draw thousands of copies from flat data, and levels of detail swap meshes by how much of the screen they cover.

<Example id="scene-particles"/>

```haxe
var fx = new GpuParticles(device, 32768);   // a ring: the oldest go first
fx.gravity = new Vec3(0, -4, 0);
renderer.use(fx);
// each frame:
fx.advance(dt);
fx.emit(x, y, z, vx, vy, vz, r, g, b, a, size0, size1, life, stretch, heat);

var rocks = new InstancedMesh(Shapes.box(device, rock), 100000);
InstancedMesh.attach(world.node("belt"), rocks);
rocks.setTransform(i, x, y, z, qx, qy, qz, qw, scale);   // nothing allocated
```

## What else

- **Automatic batching:** nodes drawing the same mesh become one instanced draw, shadows included.
- **Levels of detail:** meshes picked by screen coverage, with hysteresis so they never flicker; visibility ranges for far clusters.
- **Culling:** by the view, and by occlusion on GPUs that can query it.
- **Sprites in 3D:** camera-facing quads for clouds, halos and trees far off.
- **A million:** [GPU particles](https://helder.build/examples/#particles) and [Murmuration](https://helder.build/examples/#murmuration)'s half a million starlings.

<Reference to="scene"/>
