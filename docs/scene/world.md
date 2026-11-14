# World and nodes

A `World` is a scene graph of `Node`s: handles (an `Int`: the world, a
generation, a slot) over flat arrays of transforms, so nodes cost no
object each and a disposed node's handle is stale (`valid` false).

```haxe
var world = new World();
var arm = world.node("arm");                 // under world.root
arm.position = new Vec3(2, 0, 0);            // Vec3 and Quat: immutable values
arm.rotation = Quat.axisAngle(new Vec3(0, 0, 1), Math.PI / 2);
var hand = world.node("hand", arm);
var eye = world.node("eye");
var camera = Camera.attach(eye, Camera.perspective(Math.PI / 3, 0.1, 100));
eye.position = new Vec3(4, 3, 6);
eye.lookAt(new Vec3(0, 1, 0));
var mvp = camera.viewProjection(width / height) * hand.worldMatrix();
```

A node's transform is its parent's times its own: turn a pivot and
everything under it turns. Here a planet's orbit is a pivot at the sun,
its moon's a pivot under the planet, and the camera a node of its own:

<Example id="scene-nodes"/>

A node's `worldMatrix()` is cached until a transform above it changes.

## Stores

What nodes carry is in typed stores (`world.store(kind)`, a `StoreKind`
per kind: `Camera.KIND`, `MeshRenderer.KIND`, `Light.KIND`), made when
first used. `MeshRenderer.attach(node, mesh)`, `Light.attach(node, light)`
and `Camera.attach(node, camera)` put one on a node.

## Time

`FixedStep` runs a simulation at a fixed rate from the app loop's frames
and gives the fraction between the last two steps; `Stages` runs a frame's
work in ordered stages (`Input`, `FixedUpdate`, `Update`, `LateUpdate`,
`PreRender`).

## Fast refresh

`HotWorld.keep(world, key)`, after the world is made: under `helder dev`
the old build's transforms are put back by node path; nothing without
`-D hxmc.dev`.
