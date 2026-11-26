# Many items at once

`helder.parallel` runs one body over many items: particles, a height
field, a buffer of positions. You write the body once, as plain Haxe; it is
compiled at build time into SIMD code that handles four items at a time,
spread over every core, or run one item at a time for reference.

```haxe
import helder.parallel.Items;
import helder.parallel.Parallel;
import helder.gfx.shader.ShaderMath.*;

final particles = new Items<Particle>(100_000);

// each fixed step:
each(particles.length, i -> {
	var q = particles[i];
	var vel = q.vel.xyz * drag - vec3(0, gravity * dt, 0);
	var pos = q.pos.xyz + vel * dt;
	if (pos.y < 0) {
		pos = vec3(pos.x, -pos.y, pos.z);
		vel = vec3(vel.x, -vel.y * bounce, vel.z);
	}
	particles[i] = {pos: vec4(pos, q.pos.w + dt), vel: vec4(vel, q.vel.w)};
});

var energy = sum(particles.length, i -> 0.5 * dot(particles[i].vel, particles[i].vel));
```

`Items<T>` holds the values outside the garbage collector, in the layout
a GPU reads. A body reads what it needs from around it (`drag`, `dt`), writes
each item at its own index, and allocates nothing; the compiler says where
a body breaks those rules. Each call picks, from its own timings, whether
one core or all of them is faster, and both give exactly the same numbers,
so replays stay replays. Pass `Scalar`, `Simd` or `Jobs` last to choose
yourself.

## What else

- **map:** `map(speed, i -> length(vel[i].xyz))` fills an Items from a body.
- **Reductions:** `sum`, `min`, `max` and `reduce(n, empty, body, combine)`,
  the same bits on any number of threads.
- **Kernels:** `kernel(function(i:Int, p:{...}) ...)` names a body with its
  own typed parameters, run with `K.run(n, {...})`.
- **Not yet:** the GPU (the same bodies as compute dispatches) and TypeScript.

<Reference to="parallel"/>
