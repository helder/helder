# Physics

`helder.physics` is a small rigid-body engine for `helder.scene`: spheres, boxes and capsules that fall, collide, rest and wake, joints that hold them together, and a character controller that walks and jumps. The same steps give the same numbers on every platform, so replays and rewinds work.

<Example id="falling"/>

Add bodies, attach them to nodes, and step the world at a fixed rate. A body with no mass is static; a kinematic one moves by the velocity you give it and pushes the rest.

```haxe
var physics = new PhysicsWorld();
// a static floor (no mass), a ball moving ballNode
physics.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));
var ball = physics.add(new Body(Sphere(0.3), new Vec3(0, 4, 0)), ballNode);
// a paddle turned by its velocity, pushing, never pushed
var box = Box(new Vec3(3, 0.2, 0.2));
var paddle = physics.add(Body.kinematic(box, new Vec3(0, 0.2, 0)));
paddle.angular = new Vec3(0, 1, 0);

// each fixed step:
physics.step(dt);
var hit = physics.raycast(origin, direction);  // body, distance, point
```

## What else

- **Joints:** ball and socket, rigid rods and hinges, for chains, doors and wheels ([Chains](https://helder.build/examples/#chains)).
- **Characters:** an upright capsule steered towards a velocity, grounded by a ray, jumping and climbing steps ([Walker](https://helder.build/examples/#walker)).
- **Snapshots:** save the whole world and restore it, for rewinds, replays and branches.
- **Sleeping:** resting bodies cost nothing until something touches them.
- **No garbage:** a step allocates nothing once the world has grown to its size.
- **Not yet:** convex hulls and tall stable stacks of boxes.

<Reference to="physics"/>
