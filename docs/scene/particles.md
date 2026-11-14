# GPU particles

```haxe
var fx = new GpuParticles(device, 32768);   // a ring of 32,768: the oldest written over when full
fx.gravity = new Vec3(0, -4, 0);
fx.drag = 0.4;                              // per second
renderer.use(fx);
// each frame:
fx.advance(dt);
fx.emit(x, y, z, vx, vy, vz,   // where, how fast (units a second)
	r, g, b, a,                // linear colour (above 1: brighter than white), opacity
	size0, size1, life,        // half its side at birth and at death, seconds
	stretch, heat);            // drawn as a streak of that many seconds; whiter while young (0 to 1)
```

`GpuParticles` (`renderer.use(new GpuParticles(device, capacity))`) writes
a particle once, when it is emitted, into a ring of `capacity` particles,
and `GpuParticleShader` moves it from then on, from the feature's clock
(`time`, which the program sets or `advance` moves): its start, its
velocity slowed by `drag`, `gravity`. Nothing is simulated or allocated a
frame: the frame uploads only the particles emitted since the last (one or
two runs of the ring) and draws the ring in one instanced draw at
`AfterOpaque`, added to the scene. `fx.live` bounds the newest slots drawn
(the emission rate times the longest life): a program emitting less than
its ring holds draws less. For sparks, debris, exhaust trails, smoke and
flashes. Tap the example for a burst:

<Example id="scene-particles"/>

## A million

The same feature at a million particles alive: a spiral galaxy flung from
its core by a turning emitter, about 3,300 born a frame; on a GPU too slow
for them fewer are born and drawn (`live` lowered with the rate):

<Example id="particles" region="emit"/>

Fog fades them (light added, not turned to the fog's colour: [Fog](fog.md)).
