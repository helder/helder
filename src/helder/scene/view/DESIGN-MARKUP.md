# helder.scene.view: 3D scenes in markup, after a study of the declarative engines

This is the roadmap's phase 5 item "the scene in view's markup,
react-three-fiber's model on `helder.scene.view`" (README.md, Roadmap >
5). It studies how react-three-fiber, drei and the rest of pmndrs, Threlte,
TresJS, solid-three, A-Frame, Babylon.js, Godot, Bevy and Unity write 3D
scenes declaratively. It then sets out the foundations helder's markup for
scenes is built on: the element model, reactivity, events, assets,
composition, a standard library, the two languages, performance and the
known gaps. An implementation plan ends it.

This is the original design. See the [README](README.md) for what
ships and the API as built. The plan builds on clustered lights,
indirect light and glTF materials in [helder.scene](../README.md). Every claim about helder below was read from the source at
origin/main c7e9c050, and the file is named where it matters. Claims about
other systems cite the sources at the end, as [n].

The aim is the best model for helder, not a port of react-three-fiber.
helder's markup already differs from React's in the way that matters most:
it is compiled to direct calls, and signals update only what reads them
(src/helder/view/README.md). So most of r3f's documented pitfalls, which
come from React's re-rendering, do not apply. What helder must take from
r3f and drei is their vocabulary and their ecosystem's choices of what is
worth a tag. What it must avoid are the costs those choices hide.

## 0. Where helder starts

**What exists** (src/helder/scene/view, docs/graphics/3d.md):

- **`<Scene>`** (`SceneTags.Scene`) is a ui node: a box in ui's layout
  drawing a `World` into a texture of its size. Its children are scene
  markup (`SceneView`, a `ViewOf<SceneRenderer>`).
- **`SceneRenderer`** is helder.view's renderer for scenes
  (`implements Renders<SceneNode>`). Its elements are a closed list
  (`@:elements`): `node`, `mesh`, `instances`, `sprites`, the lights,
  `camera`, the geometry and material tags, `lines`, `text3d` and the
  helpers. Its props are declared per tag (`@:props(SceneProps)`), so a
  wrong name is a compile error at the attribute. Its events are
  declared (`@:events(SceneEvents)`), so a handler's type is checked.
- **Only the used tags link.** Each geometry and material tag is made by
  its own `element_<tag>()` (PR #14), so a program links only the
  generators and shading models its markup names. A box in the standard
  material is 473 KB natively; every tag is 1.2 MB
  (`tests/3d/size/markup.mjs`, budget 256 KB over the same scene in code).
- **Boundaries.** `<Ui>` goes back to ui inside a scene (drei's
  `<Html>`). `<Effects>` holds the post chain's effect tags
  (`EffectTags`). `<OrbitControls>`, `<TransformGizmo>` and `onTap`
  compete in the box's gesture arena.
- **Picking.** Pointer events are picked once at each pointer's press. The
  node hit owns the pointer until it lifts. A hovering mouse picks as it
  moves. The default is by bounds (`Pick.ray`); `<Scene
  pick="triangles">` picks by triangles (`Raycaster`, a BVH per primitive
  made when first picked at). A box picking by bounds links no raycaster.
- **TypeScript.** The same markup is written in TSX (helder.typescript),
  through the same planner (helder.markup). The declarations come from
  the manifest each renderer's metadata makes (src/helder/view/README.md).

**What the prototype does that the foundations must change.** These were
read from `SceneRenderer.hx`, `SceneBox.hx`, `SceneTags.hx` and the
examples:

1. **Props are stored by name in a `Map<String, Dynamic>`.**
   `SceneRenderer.setProperty` switches on the name for the node's own
   props (`position`, `rotation`...). Every other prop goes into
   `SceneNode.props`, and the element's component is made again from the
   map (`remesh`, `relight`, `recamera`). Each set boxes its value and
   looks up strings. Changing a light's intensity makes a new `Light`.
2. **Every binding is typed `Dynamic`.** `ViewRuntime.prop` binds
   `renderEffect(() -> Render.read(v), (x:Dynamic) -> Host.setProperty(n,
   name, x))`. A `Vec3` or `Quat` is an hxmc struct value
   (`@:hxmc.struct QuatData`): passed through a closure typed to return
   `Dynamic`, it is the known gap below (the Quat segfault). The examples
   work around it with a signal (`var mirror = signal(Quat...)` in
   examples/highend).
3. **Removal leaks.** `SceneRenderer.remove` detaches the world node but
   never disposes it (`Node.dispose`). The node's components (its mesh
   renderer, its light) stay in the world's stores. A `<Show>` toggled a
   thousand times leaves a thousand detached nodes. Uploads made by a
   geometry tag are released only when the tag makes a new one.
4. **One global "changed".** `SceneRenderer.changed` is a static function
   that asks every `<Scene>` box for a frame (`SceneBox.redraw`), whatever
   world changed. `animate` draws every frame.
5. **Statics shared by all boxes.** `SceneRenderer.device`, `world` and
   `pending` are statics: one device is assumed for all scenes.
6. **Motion through signals, with no owner.** examples/planets turns each
   orbit with `Clock.add(t -> { turn(Quat.axisAngle(...)); true; })`: a
   signal written every frame, through the graph, the binding and
   `setProperty` by name. The clock step is never removed, so a planet
   unmounted keeps writing its signal.
7. **`<Ui>` is a frame late.** `SceneBox.place` runs in `paintContent`,
   after ui's layout, and writes the overlay's `style.left` and `top`.
   Those are laid out by the next frame.
8. **Hand-written tags.** `SceneRenderer.hx` (585 lines) and
   `SceneProps.hx` list each tag and prop by hand. The plan calls
   for generating them from the classes.

None of these is hard to fix. They are listed because the foundations
below exist to make each of them impossible by construction, not to patch
them one by one.

## 1. The study

Each system is read for the same questions: how a prop maps to the object
model, how objects live and are disposed, how per-frame updates avoid
rebuilding, events and picking, assets and suspense, instancing,
composition and reuse, and the known performance pitfalls.

### 1.1 react-three-fiber

v9.8.2 is the stable release, "a compatibility release for React 19"; a
v10 alpha, "Going WebGPU First", makes WebGPU the default renderer
[10] [6].

- **Props to objects.** An element is a three.js class, its props its
  properties. Dashes reach nested ones (`rotation-x`,
  `material-uniforms-resolution-value`). A prop whose target has `.set()`
  is given `.set()`'s arguments, a vector is `.copy()`'d, and `scale={1}`
  is `setScalar` [1]. All of this is resolved at run time, per
  prop, per change.
- **`args`** are the constructor's arguments: "If args change later on,
  the object must naturally get reconstructed from scratch!"
  [1]
- **`attach`** is a string (`"material"`), an indexed path
  (`"material-0"`), or a function `(parent, self) => cleanup`
  [1].
- **Lifetimes.** `dispose()` is called on unmount, `dispose={null}` turns
  it off for the whole tree below [1].
- **Per frame.** `useFrame((state, delta) => ...)`, unsubscribed on
  unmount, in ascending priority; a positive priority disables automatic
  rendering [5]. `frameloop` is `always`, `demand` or `never`,
  with `invalidate()` and `advance()` [7] [8].
- **Events.** Any object that implements `raycast` gets pointer events,
  the nearest to the camera first, then bubbling; `stopPropagation()` also
  stops objects behind; capture is explicit, through `event.target`;
  `onPointerMissed` for empty clicks; the Canvas' `events` take a custom
  `compute` and `filter` [2].
- **Assets.** `useLoader` caches by URL and preloads; loading suspends to
  the nearest `<Suspense>` [5] [4].
- **Composition.** React components; `createPortal` to re-parent;
  `extend` registers a class, typed by augmenting `ThreeElements`
  [8] [6] [9].
- **Pitfalls**, its own list: "`setState` in useFrame is bad", "re-pool
  objects", "share materials and geometries", don't re-mount (toggle
  `visible`), cache with `useLoader`, instance, don't bind fast-changing
  store state reactively, `startTransition` [3]. Nearly every
  one is about React's re-render and reconcile, or about three.js's
  objects being made and freed by hand.

### 1.2 drei

drei (v10.7.9 on its site) is r3f's standard library. What became the
de facto standard, with its shape:

- **Staging**: `<Environment>` (a cubemap as `scene.environment`, presets
  "not meant for production", `ground`, `background`) [11];
  `<ContactShadows>`, "a rather expensive effect", `frames={1}` to draw it
  once [13]; `<AccumulativeShadows>` converging over `frames`
  (40) [12]; `<Bounds fit clip observe>` and `useBounds()`
  (`refresh`, `fit`, `moveTo`, `lookAt`) [16].
- **Html** ties "HTML content to any object of your scene": `transform`
  (which "can look blurry"), `occlude`, `sprite`, `distanceFactor`
  [17]. **Text** is troika's SDF text [19].
- **Assets**: `useGLTF` (useLoader and GLTFLoader, Draco and Meshopt),
  `useGLTF.preload` [18]; `useProgress` [25];
  `<Preload all>` compiles materials ahead [26].
- **Performance**: `<Instances>` ("hundreds of thousands of objects in a
  single draw call", "at the cost of CPU overhead") [14],
  `<Merged>` [15], `<Detailed>` (THREE.LOD) [22],
  `<Bvh>` (three-mesh-bvh) [23], `<AdaptiveDpr>` [24],
  `<PerformanceMonitor>` (`onIncline`, `onDecline`, `factor`,
  `flipflops`, `onFallback`) [21].
- **Controls**: `<KeyboardControls>` (a zustand store: a selector to
  read reactively, `[sub, get]` to read transiently) [20];
  `<CameraControls>` and `makeDefault` [27].
- **gltfjsx** turns a glTF into a JSX component; `--types` types its
  nodes and materials, `--instance` instances repeated geometry
  [28]. Typed access to a model is a code generator run by hand.

### 1.3 The rest of pmndrs

- **zustand**: `subscribe` binds "to a state-portion without forcing
  re-render", `getState()` reads without subscribing [29]: the fix
  for React re-rendering at frame rate.
- **leva**: a GUI from `useControls({...})` [30].
- **@react-three/rapier**: automatic colliders by default (`cuboid`,
  `ball`, `trimesh`, `hull`), `<InstancedRigidBodies>`, lazily loaded
  under `<Suspense>` [31].
- **uikit**: flexbox (yoga) panels in the 3D scene [32].
- **@react-three/postprocessing**: postprocessing's `EffectPass` "merges
  any given combination of effects"; "not (yet) meant for complex
  orchestration" [33].
- **react-three-offscreen** (experimental: the scene in a worker)
  [35], **@react-three/a11y** (roles for meshes) [34].

### 1.4 Threlte, TresJS and solid-three

- **Threlte** 8 (Svelte 5): `<T.Mesh>` for any three.js export, `is` for a
  class or an instance, props pierced with dots (`position.y`), `args`
  recreating, `attach`, disposal on unmount [36]. `useTask`
  replaced `useFrame` [44]; tasks in stages, ordered by
  `before` and `after`, invalidating the frame by default
  [37] [38]. **`on-demand` is the default
  render mode**, invalidated automatically by props, mounting and
  unmounting [39]. Events come from a plugin, with `filter`
  [40]; plugins extend `<T>` and claim props
  [41]. Extras: instancing [42], `useGltf` and
  a component generator [43].
- **TresJS** v5 (Vue): a custom renderer for Vue's template compiler
  [45], `useLoop`'s `onBeforeRender` and `onRender` by
  priority [46], `always` by default with `on-demand` and
  `manual` [47], cientos as its drei [48].
- **solid-three** is the closest to helder: Solid's signals, a component
  body that "runs once", only the expression reading a signal running
  again, no reconciler [51]; `useFrame` by priority and
  stage [50]. It says it is "still in early development,
  and is not yet ready for production use" (npm 0.2.0, 0.3.0-next)
  [49] [52]. It keeps r3f's run-time model
  otherwise: `args`, dashed props, objects made by name.

### 1.5 A-Frame

Entities are `<a-entity>`, components are HTML attributes with a `schema`
that parses strings, registered at run time; their lifecycle is `init`,
`update(oldData)`, `remove`, `tick`, `tock` [53]
[54]. `<a-mixin>` is its prefab (the rightmost wins, the
entity's attributes over all) [55]. `<a-assets>` blocks the
scene until its files are fetched (3 s timeout) [57]. Its
performance advice is r3f's in other words: pool, make no garbage in
`tick`, write transforms "at the three.js level" rather than through
`setAttribute`, stay under about 300 draw calls [56]. Every
value through the DOM is a string, parsed.

### 1.6 Babylon.js

Babylon's GUI is drawn into an `AdvancedDynamicTexture`, full screen or on
a mesh (`CreateForMesh`), with its own layout containers [58];
its 3D GUI is a utility layer, a child scene [59].
react-babylonjs covers the API "declaratively thanks to code generation"
with camelCase host elements [61]: generated from the
classes, as helder's tags will be. Babylon 9 added a frame graph and
clustered lighting [60].

### 1.7 Godot, Bevy and Unity

- **Godot**: a `.tscn` is text: external and sub resources, then nodes
  with their type and parent [62]. A saved scene "works as a
  blueprint"; a property changed on an instance overrides the packed
  scene's, with a revert [63]. Inherited scenes add nodes but
  cannot remove the base's [64]; editable children expose an
  instance's nodes [65]. `@export` fields are saved with the
  scene [66]; signals connect in the editor or in code
  [67].
- **Bevy**: required components insert what a component needs
  [71]. **BSN landed in 0.19**: `bsn!` defines templates for
  components, an expression is a patch, scenes inherit [68]
  [73], from cart's design of scenes as "patches on data"
  [72]; 0.20 reworked the syntax, and `.bsn` files are still
  to come [69]. The old scenes became `DynamicWorld` and
  `WorldAsset` [70].
- **Unity**: nested prefabs keep their links; variants inherit a base,
  their overrides winning; overrides cover values, components and children,
  shown and applied in the Inspector [74] [75]
  [76]. DOTS bakes authoring GameObjects into entities, in
  the editor only [77]: authoring and run-time data apart.

### 1.8 Side by side

| | props to objects | lifetimes | per frame | events | assets | instancing | reuse |
| --- | --- | --- | --- | --- | --- | --- | --- |
| r3f | run time, by name, dashes, `set`/`copy` | `dispose()` on unmount, `dispose={null}` | `useFrame`, `frameloop`, `invalidate` | raycast all, nearest first, through unless stopped | `useLoader` cache, Suspense | `InstancedMesh` by hand | components, portals |
| drei | | | `PerformanceMonitor`, `AdaptiveDpr` | `Bvh` | `useGLTF`, gltfjsx types | `<Instances>` (CPU per instance), `<Merged>` | |
| Threlte | `<T.X>`, dots | dispose on unmount | `useTask` stages, on-demand default | a plugin, `filter` | `useGltf` | extras | components, plugins |
| solid-three | run time, signals, no reconciler | | `useFrame` | r3f's | | | components |
| A-Frame | strings parsed by schema | `remove` | `tick` | components | `<a-assets>` blocks | pool | mixins |
| Godot | typed properties, `@export` | the tree's | `_process` | signals | resources | MultiMesh | scenes, inheritance |
| Bevy | components, templates | the ECS's | systems | picking | asset server | | BSN patches |
| Unity | serialized fields | GameObjects | `Update` | colliders | prefabs | GPU instancing | prefabs, variants |
| **helder** | **compile time, typed setters, flat stores** | **owned or borrowed, by the owner** | **`onFrame` in stages, on demand by default** | **nearest then ancestors, an arena, triangles** | **`Model.of` typed, `<Loading>`** | **automatic batching, flat `<instances>`** | **components, typed `<model>` parts** |

### 1.9 What helder takes, and what it avoids

Taken:

- r3f's vocabulary: three.js's class names as tags, `attach`, `onFrame`
  for `useFrame`, `onPointerMissed`, portals, `invalidate`, `regress`.
- drei's names for what deserves a tag where helder's apps need the same
  (section 7: chosen for apps and games, not copied), and its props' names
  (`fit`, `clip`, `occlude`, `distanceFactor`, `frames`, `flipflops`).
- Threlte's on-demand default with automatic invalidation, and its named
  stages for per-frame work.
- solid-three's model: a component runs once, a binding is one effect.
- react-babylonjs's tags generated from the classes.
- Godot's and Unity's overrides and parts, as typed props and typed model
  names; Bevy's BSN as confirmation that scenes in the language are where
  engines are heading.

Avoided:

- run-time name resolution (r3f's dashes, A-Frame's strings), `args`
  arrays and the reconstruction they hide;
- disposal decided by a flag;
- frames drawn when nothing changed (r3f's and TresJS' `always`);
- events passing through objects in front;
- a code generator for typed models (gltfjsx), and a component per
  instance (`<Instances>`);
- a state library to dodge the renderer (zustand's transient updates).

## 2. The element model

### 2.1 Tags generated from the 3D API

A tag is generated from a class, or from a factory function, marked
`@:tag`. The generator (a build macro, `SceneTagMacro`) reads the class
and writes:

- the tag's `element_<tag>()` (as PR #14's are written by hand today), so
  only used tags link;
- one typed setter per prop (section 3.1), so only used props link;
- the tag's entry in the renderer's props type (`SceneProps`, today
  hand-written), from which the compile-time checks and the TypeScript
  declarations come (`JSX.IntrinsicElements`);
- its slots for children (section 2.3).

```haxe
// a class: its public writable properties are its props
@:tag("pointLight") class PointLight implements LightKind { ... }

// a factory: its options structure's fields are its props
@:tag("toonMaterial") public static function toon(?o:ToonOptions):Material ...
@:tag("cylinderGeometry") public static function cylinder(?o:CylinderOptions):VertexData ...
```

The names are three.js's, as r3f writes them (`<pointLight>`,
`<toonMaterial>`, `<cylinderGeometry>`): r3f's intrinsic elements are the
camelCased three.js class names [1], so anyone who knows r3f
reads helder's markup at once. A component of a node (a light, a camera, a
mesh renderer, a probe, an LOD set) is a tag that makes a node and attaches
the component to it, so components are
`StoreKind`s, not node subclasses. `<pointLight position={p}/>` is a node
with a light, as r3f's `<pointLight>` is an Object3D.

The generated set replaces `SceneRenderer`'s hand-written list. A test
compares the generated tags and props against today's list (section 11,
phase M3), so the generator changes nothing a program sees.

### 2.2 Constructor props and set props

r3f has two kinds of input: `args`, the constructor's arguments, and
props, set on the object after it is made. Changing `args` destroys the
object and makes it again [1]. `args` is a positional array,
so it is the least checked part of r3f: TypeScript sees a tuple at best,
and the docs warn that changing it reconstructs the object.

helder has no `args`. Every input is a named, typed prop, and the
generator sorts each prop into one of three kinds, from the class:

| kind | what a change does | from | examples |
| --- | --- | --- | --- |
| **node** | writes the node's slot in the world's flat arrays | the node's own properties | `position`, `rotation`, `scale`, `visible`, `name`, `outline` |
| **set** | writes the component in place | a public writable property of the made object | a light's `color`, `intensity`, `range`; a material's `baseColor`, `roughness`; a camera's `fov` |
| **make** | makes the object again | an options field with no writable property | a geometry's `radiusTop`, `segments`; a material's shading model's compile-time options |

So `<pointLight intensity={i}/>` writes `light.intensity`, where the
prototype makes a new `Light`. `<cylinderGeometry radiusTop={r}/>` makes
the geometry again, as today, because a geometry's shape is its
vertices. The kind is part of the tag's declaration: the generated
TypeScript declarations say "remakes" on a make prop, and the docs page
of each tag lists them. Binding a make prop to a value that changes every
frame is legal, but the dev build's frame statistics count remakes
(`--stats`' `remade`) so that the cost is seen. That is the pitfall r3f
documents only in prose.

### 2.3 Attach: children fill typed slots

r3f attaches a child to its parent by its `attach` prop: a property path
(`attach="material"`, `attach="material-0"` for an array's item) or a
function. Materials and geometries attach by default because their names
end in `Material` and `Geometry` [1]. The prototype copies that
convention by the tag's name (`SceneRenderer.part`: `endsWith("Geometry")`).

helder attaches by type. A tag declares its slots, and a child fills the
slot whose type its value has:

```haxe
@:tag("mesh") class MeshTag {
	@:slot var geometry:VertexData;        // <boxGeometry>, <latheGeometry>...
	@:slot var material:Material;          // <toonMaterial>...
	@:slot var materials:Array<Material>;  // one a primitive, in order
}
```

- A child whose value fits exactly one slot fills it: `<mesh><boxGeometry/>
  <toonMaterial/></mesh>`, as today.
- A child that fits none is a compile error at the child's tag, naming the
  slots: "markup: <spotLight> fills no slot of <mesh> (geometry:
  VertexData, material: Material, materials: Array<Material>); a node goes
  in a <node>".
- `attach="materials"` (or `attach={1}` into an array slot) names the slot
  when two fit. A wrong name is a compile error.
- A slot filled both by a prop and by a child is a compile error, because
  one would silently win.
- `<Effects>`' children fill the post chain's slots (`ao`, `dof`, `ssr`...)
  this way, as `EffectTags` does by hand today.

Nodes are not slots. A tag whose value is a node (`node`, `mesh`, the
lights, `camera`, `<Ui>`) is a child node, put in its parent with
`Node.add`. This is the same rule as r3f's (Object3Ds are added as
children, other objects attach) [1], but checked when compiling.

### 2.4 Lifetimes: owned and borrowed

r3f calls `dispose()` on an object when it unmounts, unless
`dispose={null}` is set, which then holds for the whole tree below
[1]. Its loaders share what they load from a cache keyed by URL
[5]. So the default is right for what markup made and wrong for
what it was given, and the program must remember the flag. Threlte also
disposes on unmount [36].

helder decides by where the value came from, with no flag:

- **Owned**: what a tag made (a geometry tag's `VertexData` and its upload,
  a material tag's `Material`, a node and its components). It is disposed
  with the tag's owner (`Graph.onCleanup`): the world node by
  `Node.dispose` (its slot freed, its components' rows removed), the
  upload's reference dropped.
- **Borrowed**: what a prop was given (`geometry={rail}`, `of={rocks}`,
  `<model of={hero}>`). Markup never disposes it. The program that made
  it does.
- **Uploads are reference counted** in `SceneRenderer.meshOf`'s cache, by
  geometry, so the same geometry made by two tags is one upload, freed when
  the last tag goes.
- **Per renderer, not static.** The device, the world and the pending
  meshes are the box's (`SceneTags.BOX`, `SceneRenderer.WORLD`, contexts
  already provided across the boundary), not statics. Two `<Scene>`s on two
  windows' devices work.

A leak test checks it: a `<For>` of a thousand meshes mounted and
unmounted a hundred times leaves the world's `count` and the device's live
buffers where they started (section 9).

### 2.5 Users' own classes

r3f's `extend({ MyClass })` registers a class so that `<myClass>` works,
and in v9 its type is added to `ThreeElements` by module augmentation
[6]. A-Frame's `AFRAME.registerComponent` adds an attribute to
every entity, with a schema [54]. Both are run-time
registries.

helder's lowercase tags are the renderer's closed set (`@:elements`), and
its capitalized tags are components, functions in scope by Haxe's (or
TypeScript's) imports (src/helder/view/README.md, Markup). A user's class
marked `@:tag` gets a capitalized component generated beside it, with the
same typed props and setters:

```haxe
@:tag class Turntable implements SceneComponent {   // <Turntable speed={0.5}>...</Turntable>
	public var speed = 1.0;                          // a set prop
	public function new(node:Node) ...
	public function frame(dt:Float) node.rotation = ...;   // onFrame (section 3.3), registered while mounted
}
```

So extension needs no registry and no augmentation: importing the class
brings its tag into scope, an unused one is not linked, and its props are
checked like the built-ins'. A Godot script's `@export` fields saved with
the scene and a Bevy component on an entity are the same idea: behaviour
as a component of a node, configured by its fields [66]
[71].

## 3. Reactivity

### 3.1 Bindings write the flat stores, typed

A prop's value is one of three things, as helder.view's markup already
distinguishes (src/helder/view/README.md):

- **a constant** (a literal, a local, a plain field): set once when the
  element is made, no effect;
- **a reactive expression** (it reads a signal: `{pos()}`,
  `{p.position}` through a getter): bound by one render effect, run again
  when what it read changes;
- **motion** (a value that changes every frame): not a binding at all, but
  an `onFrame` (3.3).

The scene renderer gets a setter table (Renders' `setter`, the mechanism
ui's `NodeRenderer` uses), so the markup macro calls each prop's own typed
function, not `setProperty` by name:

```haxe
// <node rotation={Quat.axisAngle(up, angle())}/> compiles to
var n = SceneRenderer.element_node();
Graph.renderEffect(() -> (Quat.axisAngle(up, angle()) : Quat), (q:Quat) -> SceneSet.node_rotation(n, q));

// SceneSet.node_rotation, generated: a store into the world's arrays
static inline function node_rotation(n:SceneNode, q:Quat) {
	n.node.rotation = q;
	n.box.invalidate();
}
```

No string, no map, no `Dynamic`, no box on a struct, and the closure
returns `Quat`, never a struct through `Dynamic` (section 10.1). Node props
go into the world's flat arrays (`Node` is an `Int` handle;
`World.getPosition(slot)`). Set props write the component's field. Make
props mark the tag's object stale, and it is made again once per flush.

The graph's guarantees carry over unchanged:

- writes are deferred to the flush, so a frame sees one consistent state
  and two writes to a signal in a handler set the prop once;
- helder's loop flushes at the end of each event and frame, and the
  render effects' applies run in the render phase, before the box records
  its frame;
- a steady write and flush through a memo to an effect allocates nothing
  (tests/view/graph/Alloc.test.hx), and the typed setter keeps it so for
  struct values.

What helder does not do: re-run a component. A component's body runs once
when mounted (helder.view's rule). solid-three's model is the same, and
for the same reason: its component body "runs once" and only the
expression reading a signal runs again [51]. r3f re-renders
a component when its state changes, then reconciles the elements' props
against the last render [3]. helder never reconciles: a change is a call.

### 3.2 Structure in markup, motion in code

r3f's pitfalls page says "`setState` in useFrame is bad": mutate in
`useFrame` instead, and do not bind fast-changing state reactively
[3]. Threlte's `useTask` is its `useFrame` [37].
A-Frame's guidance is to update transforms "at the three.js level" in a
component's `tick`, skipping `setAttribute`, and to make no garbage there
[56].

In helder a signal written each frame is far cheaper than a React render:
one graph write, one flush, one render effect, one typed store. It is
still more than the store alone, and with 10,000 nodes it is 10,000
effects a frame. So the rule stays, measured (section 9):

- **Structure** (what exists, what it is made of, what it looks like at
  rest) is markup, and changes through signals at the rate of events.
- **Motion** (what moves every frame: a spin, a follow, a physics body, an
  animation) is code in `onFrame`, writing the nodes directly.

One rule makes the two safe together: **a prop is bound or driven, never
both.** If `onFrame` writes a node's `rotation` and the markup binds
`rotation={sig}`, the next change of `sig` overwrites the motion. A dev
build checks it: each binding keeps the value it last wrote, and before it
writes again, a value changed behind it is reported once, with the tag's
place in the source (helder.view.Source). r3f has no such check: a
`useFrame` mutation and a prop silently fight [3].

### 3.3 `onFrame` and refs

```haxe
// on an element: the node it made, the frame's seconds
<node onFrame={(n, dt) -> n.rotation = n.rotation * Quat.axisAngle(up, dt * speed)}>

// in a component's body: drei's useFrame, owned by the component
function Spinner(props:{speed:Float}):SceneView {
	var spin:Node = Node.NONE;
	Frame.on(Update, dt -> spin.rotation = spin.rotation * Quat.axisAngle(up, dt * props.speed));
	return <node ref={n -> spin = n.node}><mesh shape="box"/></node>;
}
```

- **Owned.** `Frame.on` registers in the box's `Stages` and removes itself
  with its owner (`Graph.onCleanup`), as every computation does. The leak
  in examples/planets cannot be written.
- **Staged.** The stage is the frame's (`helder.scene.Stages`: `Input`,
  `FixedUpdate`, `Update`, `LateUpdate`, `PreRender`); `onFrame` is
  `Update`. r3f orders `useFrame`s by a priority number, and a positive
  priority disables its automatic rendering [5]; Threlte orders
  tasks by stages and `before` and `after` [37]. helder's stages are named
  and the render is never taken over by a callback.
- **Untracked.** `onFrame` runs outside the graph: reading a signal there
  reads it (`peek`), it does not subscribe.
- **Keeps the box drawing.** A registered `onFrame` asks for frames while
  it is mounted. One that returns `false` is done until registered again,
  as `helder.ui.Clock`'s steps are (`Clock.add(t -> Bool)`). Section 3.4.
- **Allocates nothing.** The stage's list is iterated in place (today's
  `Stages.frame` copies each list every frame, `lists[stage].copy()`:
  removal is deferred to the end of the stage instead).
- **Refs** give the `SceneNode` (its `node`, its component), as today's
  `ref`. A ref is set when the element is made, before it is inserted, so
  `onFrame` can use it from its first call.

### 3.4 Drawing only when something changed

r3f's `frameloop="demand"` draws when its props change, and otherwise
only when `invalidate()`, which "merely requests a new frame", is called:
code that mutates objects directly must call it [4]. TresJS
draws every frame by default and has an `on-demand` mode
[47].
Threlte's `renderMode="on-demand"` invalidates automatically when its
props change and when a task that has `autoInvalidate` runs [39].
The studio's preview just learned the same lesson the hard way: drawing an
unchanged frame sixty times a second on a software GPU starved the page
of frames for 30 s (commit 40be1aa6, "the preview draws a frame only when
it changed").

helder's `<Scene>` draws on demand by default, per world:

- **What invalidates**, automatically: a binding's store (the setter calls
  `box.invalidate()`), a structural change (insert, remove), a registered
  `onFrame` that has not returned `false`, a control's glide
  (`OrbitControls.update` already asks), an `Animator` playing, live
  `GpuParticles`, an asset landing (`Assets.changed`), a resize, and a
  temporal effect still converging (`Taa`'s history).
- **Per world**, not global. The prototype's static `changed` becomes the
  world's dirty flag, read by each box drawing that world.
- **By hand**: `box.invalidate()` for code that writes the world outside
  markup (a program's `world.node(...)` moved in a coroutine).
- `render="demand"` (the default), `"always"` (today's `animate`, kept as
  an alias) or `"manual"` (only `invalidate()`).
- **Nothing recorded**: a box with nothing to draw does not record a pass
  (`beforePass`) and the window may sleep (`App.wait`), as ui's idle frames
  do.

### 3.5 Adapting to the device

r3f's `regress()` "temporarily regresses performance", and the program
reads `performance.current` to lower its quality; drei's `<AdaptiveDpr>`
cuts the pixel ratio on regress, and its `<PerformanceMonitor>` calls
`onIncline` and `onDecline` from the measured frame rate [4]
[24] [21]. helder's box already
has the knobs: `scale` and `density` (fewer pixels than the box has, a
phone's fill rate), `antialias`, and the post chain's effects.

- `<Scene regress={0.5}>`: while a control glides or a gizmo drags, the
  box draws at that share of its scale, and back after it rests.
- `<Adapt>` (section 7.7): from the frame times of the last second, steps
  `scale`, then effects off in a declared order, then back up with
  hysteresis. Its state is a signal (`quality()`), so markup can read it
  (`<Show when={quality() > 1}><Ssao/></Show>`). drei's monitor's
  `flipflops` and `onFallback` (give up after too many changes) are
  kept [21].

## 4. Events

### 4.1 What stays

The press-owned pointer model stays: the node hit at a press owns the
pointer until it lifts, so moves, release, cancel and click go to it. That
is r3f's `setPointerCapture`, done by default [2]. ui's nodes
over the box are hit first (a HUD's buttons), and `pointerEvents="none"`
lets a container through. The `SceneEvent` is one per box, refilled
(nothing allocated per event).

### 4.2 Propagation: the nearest, then its ancestors

r3f delivers an event to every object the ray intersects, nearest first,
each with its ancestors, until `stopPropagation()`: an event "passes
through" objects in front unless stopped [2]. That is not the
DOM's model, and r3f's docs spend a section on it. helder keeps the DOM's:
the nearest hit node, then its ancestors, `stop()` to end it. A program
that wants all hits calls `world.raycast` into a `HitList` itself.

Added:

- `onPointerMissed` on `<Scene>` (r3f's [2]): a press that hit no node with a
  listener (deselect on a click in empty space).
- `onDrag` (a `Pan` gesture of the box's arena) on scene elements: a drag
  that starts on a node with `onDrag` is the node's; elsewhere it is
  `<OrbitControls>`'. The gizmo already wins this way (its gesture
  accepts at a press on a handle).
- `e.instance` for `<instances>` and `<sprites>` (Hit's `instance` is
  there), so one listener on a set of 10,000 tells which was hit.

### 4.3 Picking modes and the default

The prototype picks by bounds unless `pick="triangles"`. Bounds are wrong
for anything that is not a box: a click beside a sphere, in a torus's hole
or between a tree's branches hits it. The default changes:

- **`pick="auto"`, the new default**: the bounds as the broad phase, then
  the triangles of the candidate meshes, each mesh's BVH made when first
  picked at (`Raycaster`, as `pick="triangles"` does now). Only the meshes
  that can receive an event are candidates (3 below), so the trees are made
  for those only.
- **`pick="bounds"`**: the old behaviour, linking no raycaster, for a
  build that counts its bytes. `pick="none"`: no picking.
- **Per element**: `pick="none" | "bounds" | "triangles"` on any element
  overrides its box's for its subtree (a big invisible trigger volume by
  bounds, a character by triangles, the sky not at all). In r3f an object
  picks by its own `raycast` method, which a program replaces
  [2]; drei's `<Bvh>` speeds up triangle picking with
  three-mesh-bvh [23].
- **Candidates**: only nodes with a listener, or under one, are tested.
  r3f tests any object that implements `raycast` [2], and
  Threlte's interactivity plugin takes a `filter` [40]. The
  renderer keeps the set
  (a listener added or removed updates it), so a scene of 10,000 static
  nodes and one button tests one.
- **Hover coalesced**: a hovering mouse picks once a frame, at its last
  position, not at each move event (a 1,000 Hz mouse would pick 16 times a
  frame).

The size cost of `auto` against `bounds` (the raycaster and the BVH
builder) is measured by `tests/3d/size/markup.mjs` when it lands and said
in the docs.

### 4.4 The gesture arena

Taps, drags, the controls and the gizmo stay recognisers in the box's
arena (helder.ui.gesture). The order is the arena's: a recogniser that
accepts at a press (the gizmo on a handle, `onDrag` on a node) wins, and
otherwise the first to recognise its gesture does (a tap or an orbit).
r3f has no arena: its events and its controls (drei's `<OrbitControls>`,
`<CameraControls>` [27]) each listen to the canvas, and
a program decides between them itself.

## 5. Assets

### 5.1 Models in markup, typed

`Model.of("models/hero.glb")` is already typed when compiling: its nodes,
meshes, materials and animations are fields named from the file, so a typo
is a compile error (src/helder/scene/render/Model.hx). r3f gets typed
access only from gltfjsx, a code generator run on the file that writes a
component with the nodes and materials as typed fields [28]; when the
file changes, the component must be generated again.

```haxe
var car = Model.of("models/car.glb");

<model of={car} position={p}/>                               // the whole model
<model of={car} node={car.nodes.Wheel_FL} position={w}/>     // one sub-tree, by its typed name
<model of={car} materials={{Body: paint, Glass: tinted}}/>   // overrides, by the file's typed material names
<model of={car} ref={m -> m.find(car.nodes.Door_L)}/>        // a node of the instance, typed
<model of={car} animation={car.animations.Idle} loop/>       // an Animator on it, playing
```

- `<model>` calls `Model.instantiate` (GPU meshes made once per model and
  shared by every instance, as today) and owns the nodes it made.
- `node={...}` instantiates the sub-tree under that node only. That is
  new in `Model` (`instantiateNode`), and is Godot's "editable children"
  and Unity's nested prefabs read the other way: a model is a library of
  parts, picked by name [63] [75].
- `materials={...}` is typed from the model's material names (`M`, the
  macro's type for `model.materials`): a wrong name is a compile error.
  This is a prefab override in Unity's sense, without the serialized
  diff [75].
- The model is borrowed (2.4): unmounting a `<model>` disposes its
  instance's nodes, never the model's GPU meshes.

### 5.2 Loading and placeholders

A model loaded in the background is an `Asset` (`Asset.model(path)`, or
`Model.of(path, Lazy)`), an async memo of helder.view's graph. helder.view
already has Solid 2's `<Loading>`: its fallback shows while what its
children read on their first load is pending, and a later reload is held,
with no fallback between (no torn frames) (src/helder/view/README.md,
"Values not ready yet"). It works across the scene boundary because the
scene renderer has markers:

```haxe
<Loading fallback={<mesh shape="box" color={grey}/>}>     // a placeholder in the world
	<model of={Asset.model("models/level.glb")}/>
</Loading>
<Loading fallback={<Ui><Spinner/></Ui>}>...</Loading>     // or ui over the box
```

This is r3f's `<Suspense>` around `useGLTF`, and drei's `useProgress`
for the loading screen [4] [18] [25]. Two
differences:

- a model's nodes are not made while it is pending. r3f suspends the
  component and React throws away the work above the boundary; helder's
  graph holds the pending computation and runs only it when the value
  lands;
- `Assets.progress` (bytes loaded of the bytes known) is a signal, so a
  progress bar is a binding, not a hook.

Preloading is the default for `Model.of` (read before main), and
`Asset.model(path).load()` starts one early: drei's `useGLTF.preload`
[18]. drei's `<Preload>` also compiles materials ahead, because
otherwise they compile "only when they hit the frustrum" [26];
helder's are compiled at build time.

### 5.3 Reloading

Under `helder dev`, a model's file changed is loaded again into the same
`Model` (`replace`: the meshes' primitives and materials swapped in the
instances). Markup's bindings and overrides stay on the nodes they were
on. A node renamed or removed in the file is a compile error at the next
build, at the markup naming it.

## 6. Composition

### 6.1 Components are prefabs

A component returning `SceneView` is a prefab: a function of typed props
returning a sub-tree, instanced as many times as it is used.

| prefab feature | Unity [75] | Godot [63] | helder |
| --- | --- | --- | --- |
| a reusable sub-tree | prefab asset | scene (.tscn) instanced | component `function Tree(props):SceneView` |
| overrides per instance | serialized property overrides | changed properties of an instanced scene | props |
| variants | prefab variant | inherited scene | a component wrapping another with props set |
| nested | nested prefabs | scenes in scenes | components in components |
| editable children | unpack, or overrides on children | editable children | typed `ref`s, `<model node=...>` |
| the file format | YAML, serialized | text `.tscn` | the markup in `.hx` or `.tsx` |

helder keeps no scene format of its own (README.md, phase 6: "Scenes and
ui stay markup in `.hx`"): the studio edits the literal. Bevy has moved the
same way: BSN landed in 0.19 as the `bsn!` macro, scenes as patches of
component templates with inheritance, and `.bsn` files are still to come
after 0.20 [68] [69]. Scenes written in the language keep one
source of truth, which Unity's and Godot's editor files do not have beside
code.

### 6.2 Instancing

drei's `<Instances>` and `<Instance>` make one `InstancedMesh` with a
React component per instance: one draw call, which drei says "comes at the
cost of CPU overhead"; `<Merged>` does the same for several meshes
[14] [15]. helder has more of this already:

- **Nodes drawing the same primitive are one instanced draw**
  automatically (docs/scene/instancing.md, "Batched nodes"). A thousand
  `<mesh geometry={rock} material={stone}>` are one draw with no
  `<Instances>`; markup's meshes share uploads by geometry and material
  (`SceneRenderer.meshOf`). So the reason for drei's `<Instances>` (the
  draw calls) is gone. What is left is the per-node cost: a world slot,
  and one effect per bound prop.
- **Above about 10,000**, `<instances of={set}/>` draws an `InstancedMesh`
  from flat data (exists), written in an `onFrame` (`set.setTransform(i,
  ...)`, nothing allocated). Its events give `e.instance` (4.2).
- **`<instances count={n} each={(i, w) -> ...}>`**: the set made by the
  tag (owned), its instances written by a function of the index into a
  writer, once when made and again when what `each` reads changes. A field
  of trees from a signal of their seed is one effect, not 10,000.
- **`<merged>`** (static batching: the children's geometries baked into one
  when made) is low priority, because the instancing above already makes
  one draw.

### 6.3 Portals, render targets and nested scenes

- **`<Portal into={node}>`**: its children are made under another node of
  the same world (r3f's `createPortal`, "a React feature for
  re-parenting") [8], owned where the
  portal is written. It is `Render.insert` into that node, which the
  renderer has.
- **`<RenderTexture>`**: a world drawn into a texture that a material reads
  (drei's `<RenderTexture>`). Its children are another world's
  markup, its value a `Texture` given to a material's slot
  (`<standardMaterial><RenderTexture attach="baseColorTexture" world={tv}
  camera={c}>...</RenderTexture></standardMaterial>`). It draws on demand
  as a box does, and only when the material using it is drawn.
- **`<Ui transform>`**: ui's markup drawn into a texture on a plane in the
  world (drei's `<Html transform>`, @react-three/uikit's panels) [32].
  helder.ui is already a flexbox layout drawn on the GPU, so a panel in the
  world is ui drawn into a render target, its pointer events those of the
  plane's uv (the triangle picking of 4.3). drei's `transform` mode,
  CSS 3D transforms over the canvas, "can look blurry" [17].
- **A `<Scene>` in a scene** is a ui node, so it goes in a `<Ui>`: a
  minimap or a viewcube over the box. Its world is its own or shared (two
  cameras on one world).
- **Contexts** reach across every boundary (they do today: `<Scene>`
  provides its world and box to its children and runs them in its owner).

## 7. A standard library for apps and games

drei is react-three-fiber's standard library in all but name: dozens of
helpers, of which a few are in nearly every r3f project (OrbitControls,
Environment, useGLTF, Html, Text, ContactShadows, Bounds, Instances)
[11] [18] [17] [19] [13]
[16] [14]. helder's is `helder.scene.view.extras`
(`import helder.scene.view.Extras.*`), Threlte's name for the same thing
[42]: capitalized components over the 3D API, each its own
function, so an unused one is not linked.

It is not a drei clone. helder is both a ui framework and a game
framework, so an extra earns its place by making a real app of either
kind shorter to write. Two apps are the test cases, and each extra names
the one it shortens:

- **a game**: Little Skies (helder/little-skies), a mobile golf game. It
  hand-rolls today what P0's physics and P1's camera rig, triggers, tweens
  and audio would give it;
- **a ui app with 3D**: a product viewer or configurator, data
  visualisation, 3D widgets inside a ui layout. Its needs are staging,
  selection, accessibility, theming and a battery that lasts.

### 7.1 P0: the core both kinds of app need

| helder | drei, and others | on | for |
| --- | --- | --- | --- |
| `<model>` (5.1) | `useGLTF`, `<Clone>`, gltfjsx | `Model` | both |
| `<Bounds fit clip observe margin>`, `fitCamera(box, nodes)` | `<Bounds>`, `useBounds` | `Aabb`, the camera | both |
| `<Environment preset file background blur intensity>` | `<Environment>` | `Environment`, `Sky` (and the environment prefilter) | both |
| `<ContactShadows opacity blur far resolution>` | `<ContactShadows>` | a depth pass from below into a blurred texture on a plane (works on the GL ES 3.0 floor) | both |
| `<Ui>` in the world, made exact (7.2, 10.2) | `<Html>`, `<Html transform>`, uikit | ui, the box's depth, render targets | both |
| `<OrbitControls>`, `<TransformGizmo>` (exist) | `<OrbitControls>`, `<TransformControls>` | the arena | both |
| `<Controls map={...}>`, `controls("jump")` | `<KeyboardControls>` | `InputMap` (keys, pads, touch zones, sticks) | both |
| `<Physics gravity>`, `<RigidBody type collider>` (auto colliders), `<Joint>` (7.3) | @react-three/rapier's `<Physics>`, `<RigidBody>`, auto colliders | helder.physics | games first |
| the interaction layer: `hover`, `selected`, `<Draggable plane axis snap>`, focus and accessibility (7.4) | drei's `<Select>`, `<DragControls>`, @react-three/a11y | phase 2's outlines, the arena, ui's focus and accessibility tree | ui apps first |

### 7.2 `<Ui>` in the world, helder's own

No web stack has this: the world's labels, panels and widgets are
helder.ui itself, drawn on the same GPU, in the same input arena, with the
same text and layout. drei's `<Html>` is the DOM over a canvas, a frame
behind and blind to depth unless it raycasts; its `transform` mode "can
look blurry" [17]. So `<Ui>` gets P0's focus, to this bar:

- **No lag.** Its place is the frame's own camera's (10.2).
- **Occluded by depth, per pixel.** A label behind a mesh is hidden
  where the mesh covers it, read from the box's depth, not drei's one ray
  to its centre. `occlude="ray"` stays the cheap opt-in.
- **Crisp at any distance.** Over the box (`<Ui>`): ui's own pixels,
  `distanceFactor` scaling its layout, never a texture. On a plane in the
  world (`<Ui transform>`, promoted from P2): drawn into a render target at
  the density it covers on screen this frame, again when that changes past
  a step, so it is sharp up close and cheap far away.
- **The same input.** Its pointer events are ui's, in the box's arena: a
  button on a panel in the world wins its press against the orbit as a
  HUD's does, through the plane's uv (4.3's triangle picking).
- **Measured.** Its tests (10.2) check the pixels in the frame the camera
  moved, an occluded label's pixels, and a world panel's text against the
  same text drawn flat at the same size.

### 7.3 Physics

Promoted from P1: Little Skies is a physics game, and most games are. In
@react-three/rapier "RigidBodies generate automatic colliders by
default" from the meshes inside (`cuboid`, `ball`, `trimesh`, `hull`), and
`<InstancedRigidBodies>` gives each instance a body; Rapier loads lazily,
so `<Physics>` sits in a `<Suspense>` [31]. helder's `<RigidBody>` does
the same on helder.physics: `collider="auto"` fits a box, sphere or
capsule to the children's bounds; `"box" | "sphere" | "capsule" | "mesh"`
with sizes; `type="dynamic" | "fixed" | "kinematic"`. `<instances>` takes
bodies too.

The fixed step and interpolation are done right, not left to the
program:

- the world steps in `FixedUpdate`, at `<Physics rate>` (60 a second by
  default), as many steps as the frame holds, capped so that a slow frame
  does not spiral (`FixedStep`);
- a body's node is written in `PreRender`, interpolated between the last
  two steps by the clock's alpha, so motion is smooth at any refresh rate
  (a 120 Hz phone, a frame dropped) while the game's logic reads the
  step's exact state;
- a body's transform is driven (3.2), so its `position` prop is its
  start, not a binding: the dev check says so if it changes;
- events: `onContact`, `onSleep`, and 7.5's triggers;
- the box keeps drawing while a body is awake, and stops when all sleep
  (3.4).

### 7.4 The interaction layer

What every ui app with 3D writes by hand, and what a game's editor and
menus need:

- **Hover and selection.** `hover` and `selected` on any element draw
  phase 2's outlines (`Outline`'s groups), bound to the node's own hover
  and to a selection signal: `<model of={car} selected={pick() == car}/>`.
  `<Selection value={sel}>` keeps one or many, and a tap in empty space
  (`onPointerMissed`) clears it.
- **Dragging.** `<Draggable plane="xz" axis snap={0.5} onDrag>` moves its
  children on a plane or along an axis, in the arena (4.4); `surface`
  snaps them to what is under the pointer (a part placed on a table, a
  piece on a board).
- **Focus and accessibility.** A pickable node (one with a listener or a
  `role`) is focusable: Tab and the arrows move between them, Enter and
  Space press, the focused one is outlined. Each is a node of ui's
  accessibility tree (`role`, `label`, `description`) at its projected
  bounds, so a screen reader finds "Wheel, button" in a configurator and
  VoiceOver's touch exploration works over the box.

### 7.5 P1, games

| helder | others | on |
| --- | --- | --- |
| `<CameraRig follow behind lookAhead ease>`: follow, orbit behind, look ahead of the velocity, eased transitions between rigs (Little Skies hand-rolls one) | Cinemachine, Godot's `SpringArm3D` | `LateUpdate`, the camera |
| triggers and sensors: `<Trigger shape onEnter onExit>` | rapier's sensors, Unity's triggers | helder.physics' sensors, else bounds |
| tweens and timelines: `tween(node, {position: p}, 0.4, easeOut)`, `<Timeline>` | GSAP, drei's `<Float>` | `onFrame` and ui's transitions and easings (helder.ui.motion): ui and 3D animate the same way |
| spatial audio: `<Sound src loop distance>` at a node | drei's `<PositionalAudio>` | helder.os's audio, panned and attenuated from the camera |
| scene and state switching: a `<Switch>` of scenes, kept or disposed (2.4), a fade between | Godot's `change_scene`, Unity's scenes | `<Show>`, `<Loading>` |
| `<text3d>` (exists), `<Label>` (flat text facing the camera, the glyph atlas) | `<Text>` (troika SDF), `<Text3D>`, `<Billboard>` | helder.text, `Sprites` |

### 7.6 P1, ui apps

| helder | others | on |
| --- | --- | --- |
| `<Stage>` (environment, contact shadow and bounds in one) and `<Center>`: a product viewer's defaults | `<Stage>`, `<Center>` | 7.1 |
| theming: the environment, the clear colour and materials' colours following ui's light and dark theme | | ui's theme |
| drawing on demand by default (3.4), measured for battery: an idle box records no pass | r3f's `frameloop="demand"` | 3.4 |
| scroll- and layout-linked 3D: a `<Scene>` reading ui's scroll and its own transitions (`progress={scroll()}`) | drei's `<ScrollControls>` | ui's scroll and motion signals |
| `<Lod>` | `<Detailed>` | `Lod` |
| `<Loading>` (exists), `Assets.progress` | `<Suspense>`, `<Loader>`, `useProgress`, `<Preload>` | helder.asset |
| `<Stats>` | `<Stats>`, `<StatsGl>`, r3f-perf | `--stats`' counters |

### 7.7 Adaptive quality

`<Adapt>` and `regress` (3.5) stay, to a high bar, because a wrong step
is worse than none: a scene that flickers between qualities, or one that
drops its resolution when an effect was the cost.

- **Hysteresis**: it steps down after a sustained drop and up only after
  a longer sustained margin, and gives up after `flipflops` changes
  (`onFallback`) [21].
- **Per feature, in a declared order**: effects first (the costliest
  first, as measured), then resolution (`scale`), not the reverse unless
  the program says so.
- **Measured on real devices** (the pack lanes' phones, Little Skies on a
  mid-range Android), not only on CI's software GPU, whose costs are not
  a phone's.

### 7.8 P2, and examples rather than API

`<RenderTexture>`, `<Portal>` (6.3), `<GizmoHelper>` (a viewcube, a nested
`<Scene>`) and `<AccumulativeShadows>` (soft shadows converged over
frames, then still). The flourishes (`<Float>`, `<Sparkles>`, `<Stars>`,
`<Cloud>`) may be examples rather than API: each is a few lines of
`onFrame`, `GpuParticles` or `Sprites`, better copied and changed than
configured.

### 7.9 Not shipped

drei's materials that exist for three.js's limits
(`MeshReflectorMaterial`, where helder has `Ssr`; `MeshTransmissionMaterial`,
where helder.scene has `Transmission`), its camera-shake and scroll
helpers (an `onFrame` each), and leva (helder's studio has an inspector
that edits the literal, README.md phase 6) [30].

**State outside the tree.** zustand's "transient updates" subscribe to the
store outside React so that a value changing each frame skips React's
render [29]. helder needs no library for this: signals live in any
object graph, belong to no owner, and an `onFrame` reads them with `peek`
(src/helder/view/README.md, Signals). A game's state is plain objects
with signals where markup reads them.

## 8. One model in Haxe and TSX

- **The same tags.** The generator writes the props type the manifest
  reads , so the TSX declarations
  (`JSX.IntrinsicElements` for `SceneRenderer`) are generated, never
  written: a tag added in Haxe is in TSX in the same build.
- **Checked when compiling, both.** Haxe checks a prop's name today and its
  type with the typed setters (3.1): `<pointLight intensity="bright"/>` is
  an error at the attribute. TSX gets the same through tsgo from the
  declarations. Slots (2.3) and handlers (`@:events`) are checked in both.
- **The same semantics.** TSX's holes are bound when they read, as Haxe's
  are (README.md, TypeScript quick start), so `<node position={pos()}>` is
  one binding in both, and `onFrame` and `Frame.on` are the same functions.
- **Only what is used links.** One `element_<tag>` per tag and one setter
  per (tag, prop), each a function the markup calls directly, so dead code
  elimination drops the rest. The extras are components, dropped the same
  way. `tests/3d/size/markup.mjs` grows a row per family: Tiny still holds
  no other generator, no shading model, no extras component, no raycaster
  under `pick="bounds"`, and markup's cost over the same scene in code stays
  in its 256 KB budget, natively and as wasm32.
- **Errors at the tag, in both languages**: a prop a tag does not take
  (today), a prop's type, a child that fills no slot, a slot filled twice,
  a handler's type, an extras component outside a `<Scene>`.

## 9. Performance targets and how they are measured

### 9.1 The benchmark

`tests/bench/SceneMarkupBench.hx` (and its TypeScript twin) builds the same
scene five ways, at 1,000 and 10,000 nodes (each a mesh of one shared
geometry and material, so one instanced draw):

- **Code**: `world.node`, `MeshRenderer.attach`, a loop writing positions.
- **Markup, constant**: `<For>` of `<mesh position={p}/>`, nothing bound.
- **Markup, signals**: each mesh's `position={pos[i]()}`, every signal
  written each frame (the worst case, the pattern examples/planets uses).
- **Markup, onFrame**: each mesh's own `onFrame` writing its node.
- **Markup, one onFrame**: one `Frame.on` writing all the nodes (the
  recommended pattern).

It measures, natively and as wasm32-wasi, on the bench lane (`bun run test
bench`, results in `tests/bench/results/scene-markup.md`):

- mounting: milliseconds and bytes allocated;
- unmounting: milliseconds, and the world's live nodes, the device's
  buffers and the GC heap back where they started (the leak check of 2.4);
- a frame with every node moving: CPU milliseconds from the stages to the
  recorded pass, and bytes allocated (GcStats);
- an idle frame: passes recorded, draws and bytes allocated.

### 9.2 Targets

| measure | 1,000 nodes | 10,000 nodes |
| --- | --- | --- |
| mount, markup against code | at most 2× | at most 2× |
| unmount | everything freed | everything freed |
| a frame, one onFrame, against code | at most 1.1× | at most 1.1× |
| a frame, an onFrame each, against code | at most 1.5× | at most 1.5× |
| a frame, a signal each, against code | at most 3× | measured, said |
| bytes allocated a steady frame, any variant | 0 | 0 |
| an idle frame | no pass recorded, no draw | no pass recorded, no draw |
| size, markup over code | within the 256 KB budget | |

The prototype is measured first (phase M0), so each phase's gain is a
number, not a claim.

### 9.3 Per-frame allocation rules

Every per-frame path keeps the renderer's allocation rule (nothing allocated
per frame), and the benchmark checks it. In markup that means:

1. no closure made per frame (a binding's closure is made once, when the
   element is made);
2. no struct boxed: values go through typed setters, never `Dynamic`;
3. no string compared or map looked up per set;
4. stage lists iterated in place, removals deferred;
5. events: one `SceneEvent` per box, refilled (as today); hover picked once
   a frame;
6. the dirty flag a field, not a list of changes;
7. `For`'s rows and markers made at mount and on changes of the list, never
   per frame.

## 10. The known gaps, fixed

### 10.1 The Quat segfault

**Symptom.** An inline expression returning a `Quat` (or another struct
value) as a prop, `rotation={Quat.axisAngle(up, a())}`, crashes natively.
The examples bind a `Signal<Quat>` instead (examples/highend's `mirror`),
and the README's roadmap lists it: "hxmc passing a closure returning a
struct value (a `Vec3`) where a binding expects one".

**Cause.** Every binding goes through `ViewRuntime.prop`, typed `Dynamic`:
the markup macro passes the expression as a function, which hxmc must then
treat as a function returning `Dynamic`. A `Quat` is an abstract over
`@:hxmc.struct QuatData`, a value copied, never allocated
(src/helder/scene/math/Quat.hx). A closure returning a struct by value,
used where a function returning `Dynamic` is expected, is the conversion
hxmc does not make yet, so the caller reads a struct's bytes as a
reference. `OrbitControls`' `target` works round it in the same way
(`Render.read(props.target) : Dynamic`, "hxmc passes no function of a
struct (Vec3) as one of another type", SceneTags.hx).

**Fix**, in three parts:

1. **Typed bindings** (3.1): the markup macro types the attribute's
   expression against the setter's parameter and emits `renderEffect(() ->
   (e : Quat), (q:Quat) -> set(n, q))`. No closure of a struct ever meets
   `Dynamic`. This removes the crash for every scene prop and every struct
   type (`Vec2`, `Vec3`, `Vec4`, `Quat`, `Mat4`, `Aabb`).
2. **hxmc**: a test of the conversion itself (a `Void->Quat` passed as
   `Void->Dynamic`), fixed by boxing at the conversion, or rejected when
   compiling. That is an hxmc task, tracked there; helder does not wait for
   it.
3. **Never a crash meanwhile**: until hxmc converts, the markup macro
   rejects a struct-typed expression on a path that would go through
   `Dynamic` (a renderer without typed setters), with an error that names
   the fix: "markup: rotation's value is a Quat (a struct value), which a
   function returning Dynamic cannot return yet: bind a Signal<Quat>, or
   give the renderer typed setters".

Tests: `tests/3d-ui/SceneUiTest.hx` binds inline `Quat`, `Vec3` and `Vec4`
expressions (constant and reactive), natively and as wasm32-wasi;
`tests/view/reject` holds the error.

### 10.2 `<Ui>`'s one-frame lag

**Cause.** `SceneBox.place` projects each overlay's node with the camera
during `paintContent` and writes the overlay's `style.left` and `top`.
Paint comes after layout, so the new place is laid out in the next frame:
under an orbiting camera, labels trail their nodes by a frame.

**Fix.** The overlay's place is a paint-time translation, not a layout
input:

1. The overlay is laid out once at the box's origin (its size from its
   content, as now).
2. Each frame, after the stages (the camera has moved) and before paint,
   the box projects each overlay's node with the camera it will draw with,
   and sets the overlay's translation, which ui applies when it paints, as
   CSS's `transform` moves a box without laying anything out.
3. The box's own drawing and its overlays' use the same view matrix, read
   once a frame, so they cannot disagree.

Its hit testing follows the translation: ui hit-tests through transforms
already (`Node.transformMatrix`), and a transform's change asks for paint,
not layout (src/helder/ui/Node.hx).

Added with it: `occlude` (hidden when the ray from the camera to the node
hits a nearer mesh: one raycast a frame per overlay, opt-in),
`distanceFactor` (scaled by the distance, as drei's), and `center`
(the default today, kept).

Test: `tests/3d-ui/SurfaceTest.hx`, with the camera moved in one frame,
checks the overlay's pixels at the node's projection in that same frame.

### 10.3 Picking's defaults

Section 4.3: `auto` (bounds then triangles) by default, `bounds` and `none`
as choices, `pick` per element, only nodes with listeners tested, hover
picked once a frame. Tests in `tests/3d-ui/SurfaceTest.hx`: a click in a
torus's hole hits what is behind it; a click on a mesh without a listener
under one with none goes to the scene's `onPointerMissed`; ten thousand
static meshes and one with a listener build one BVH.

## 11. Implementation plan, in phases

Each phase records its proposed tests and examples. The current guide is
in [3D graphics](/docs/graphics/3d.md).

### Phase M0: the baseline

- `SceneMarkupBench` (9.1) on today's prototype; its numbers in
  `tests/bench/results/scene-markup.md`.
- A leak test of today's remove (expected to fail, marked so).

Tests: the bench lane. Docs: none (the results file).

### Phase M1: typed bindings, and the Quat segfault

- `SceneRenderer`'s setter table: one typed setter per node prop and per
  set prop, written by hand for today's tags (the generator comes in M3).
- The props' types checked when compiling, the Map kept for make props
  only.
- The struct-typed reject on `Dynamic` paths (10.1, part 3), and the hxmc
  issue filed with its test (part 2).
- examples/highend's `mirror` signal removed: an inline `Quat`.

Tests: 10.1's; `tests/view/reject` for a prop's wrong type; the bench
again. Docs: docs/graphics/3d.md's Status rewritten (no "struct values
through a Signal").

### Phase M2: lifetimes, demand drawing, `onFrame`

- Owned and borrowed (2.4): `Node.dispose` on remove, uploads counted, the
  statics moved to the box.
- Demand drawing per world (3.4), `render=`, `invalidate()`; `animate` an
  alias.
- `onFrame` and `Frame.on` (3.3), owned and staged; `Stages` iterated in
  place.
- The bound-or-driven dev check (3.2).
- examples/planets rewritten with `onFrame` (and the clock steps gone).

Tests: the leak test passing; a box idle for 100 frames records no pass
(`--stats`); an `onFrame` unmounted stops; GcStats on a frame of each.
Docs: "Motion and onFrame" and "When a scene draws" sections in
docs/graphics/3d.md.

### Phase M3: the tag generator

- `@:tag` on classes and factories, `@:slot`, `SceneTagMacro`: the
  elements, setters, `SceneProps` and the TSX declarations generated.
- Typed slots (2.3) replacing `part()`'s names.
- Users' `@:tag` classes as components (2.5).
- Lighting and material classes tagged: the clustered lights' kinds,
  `rectAreaLight`, `reflectionProbe`, `lightProbe`, `Lod`, the physical
  material's options.

Tests: the generated list equal to today's (a golden of tags and props);
rejects (a child that fills no slot, a slot filled twice, an unknown
slot); `tests/typescript/definitions` (the declarations checked); the size
check per family. Example: `examples/turntable` (a user's tag). Docs: "Your
own tags" in docs/graphics/3d.md; each tag's props listed on its page
(generated).

### Phase M4: events, picking, `<Ui>`

- `pick="auto"` by default, `pick` per element, the candidate set,
  coalesced hover (4.3).
- `onPointerMissed`, `onDrag`, `e.instance` (4.2).
- `<Ui>` exact (10.2), `occlude`, `distanceFactor`.

Tests: 10.2's and 10.3's; the size of `auto` against `bounds`. Example:
examples/picking without `pick="triangles"` (the default does it);
examples/planets' labels under an orbit. Docs: docs/scene/picking.md's
markup section, and `<Ui>`'s.

### Phase M5: models in markup

- `<model>` (5.1): `node`, `materials`, `animation`, typed refs;
  `Model.instantiateNode`.
- `<Loading>` placeholders in the world and over it (5.2),
  `Assets.progress`.

Tests: `tests/3d-ui` (a sub-tree instantiated, an override, a
placeholder replaced when the model lands, a reload keeping the
bindings); rejects (a node or material name not in the file). Example:
`examples/configurator` (a car from glTF, its paint and wheels chosen in
ui, a loading placeholder). Docs: "Models in markup" in
docs/scene/models.md.

### Phase M6: the P0 core

- `<Bounds>` and `fitCamera`, `<Environment>`, `<ContactShadows>`,
  `<Controls>` (7.1).
- `<Ui>` in the world to 7.2's bar: per-pixel depth occlusion, `<Ui
  transform>` at the density it covers, its events in the arena.
- The interaction layer (7.4): `hover`, `selected`, `<Selection>`,
  `<Draggable>`, focus and the accessibility tree.

Tests: golden frames for `<ContactShadows>` and `<Environment>`
(tests/3d's frames, natively and on WebGPU and WebGL2); `<Bounds>`'s fit
checked by numbers; 7.2's pixels; a drag on a plane and one snapped to a
surface, by numbers; Tab through three pickable nodes, and their nodes in
the accessibility tree. Example: `examples/configurator` (M5's) gains
selection, dragging and focus. Docs: docs/scene/extras.md, a section per
component, each with a live example.

### Phase M7: physics

- `<Physics>`, `<RigidBody>`, `<Joint>` on helder.physics, auto colliders,
  instanced bodies, the fixed step and interpolation (7.3).

Tests: a body's node after N steps equal to the same world in code
(natively and as wasm32-wasi, the same numbers on each, as helder.physics
tests); a node interpolated between two steps at the clock's alpha;
GcStats on a step with markup; a box idle once every body sleeps.
Example: examples/falling in markup beside the code version. Docs:
docs/scene/extras.md's physics section.

### Phase M8: P1 for games

- `<CameraRig>`, `<Trigger>`, tweens and `<Timeline>` on ui's easings,
  `<Sound>`, scene switching, `<Label>` (7.5).

Tests: a rig's camera after N frames, by numbers; a trigger's enter and
exit, once each; a tween's values at its ends and midpoint equal to ui's
transition's; GcStats on a frame with each. Example: a small course in
markup (a ball, a rig, the hole a trigger). Moving Little Skies onto them
is the check that they shorten a real game. Docs: docs/scene/extras.md's
games section.

### Phase M9: P1 for ui apps, and adaptive quality

- `<Stage>`, `<Center>`, theming, scroll- and layout-linked scenes,
  `<Lod>`, `Assets.progress`, `<Stats>` (7.6).
- `<Adapt>` and `regress` to 7.7's bar.

Tests: a theme switched redraws the box once, in the new colours; an
idle viewer records no pass in 100 frames; `<Adapt>` steps effects down
before scale under a forced slow frame, and does not flip under a noisy
one. Measured on the pack lanes' devices, the numbers in the docs.
Example: `examples/configurator` gains `<Stage>` and theming; a data
visualisation in a scrolling ui page. Docs: docs/scene/extras.md's ui
apps section.

### Phase M10: composition and P2

- `<Portal>`, `<RenderTexture>`, `<GizmoHelper>`, `<AccumulativeShadows>`,
  `<instances count each>` (6.2, 6.3, 7.8); the flourishes as examples.

Tests: a render texture's frame. Example: `examples/arcade` (a screen in
the world showing another world). Docs: "Composition" in
docs/graphics/3d.md.

The benchmark (M0) runs again at the end of each phase, and its results
file keeps each phase's row.

## 12. Decisions

1. **Tags are generated from `@:tag` classes and factories**, with
   three.js's names. Hand-written lists go (2.1).
2. **No `args`.** Every input is a named, typed prop of one of three kinds:
   node, set or make. A make prop remakes the object, and that is declared
   and counted (2.2).
3. **Children fill typed slots.** A child is matched by its value's type,
   not its tag's name, and an ambiguous or unfilled slot is a compile
   error (2.3).
4. **Owned or borrowed, never a flag.** What a tag made dies with its
   owner. What it was given is never disposed. Uploads are counted (2.4).
5. **Users' classes become capitalized components**, generated, in scope
   by import. There is no run-time registry (2.5).
6. **Bindings are typed setters into the flat stores.** No name, no map,
   no `Dynamic`. This also removes the Quat segfault (3.1, 10.1).
7. **Structure is markup, motion is `onFrame`.** `onFrame` is owned and
   staged, and a prop is bound or driven, never both (dev-checked) (3.2,
   3.3).
8. **On demand by default, per world.** Invalidation is automatic, and a
   box draws only when something changed (3.4).
9. **Events go to the nearest node, then its ancestors.** Picking is by
   triangles by default (`auto`), tests only nodes that can receive the
   event, and coalesces hover. Gestures stay in the arena (4).
10. **`<model>` instantiates typed models**, whole or by typed sub-tree,
    with overrides by typed material names. Loading uses `<Loading>`
    (5).
11. **Components are prefabs, and markup is the scene format.** There is
    no separate file (6.1).
12. **`helder.scene.view.extras` serves apps and games**, not drei's
    list: each extra makes Little Skies or a ui app with 3D shorter to
    write. P0 is the core both need (models, staging, `<Ui>` in the world,
    controls, physics, interaction); P1 is split into games' and ui
    apps'. Each is linked only when used, measured against code at 1,000
    and 10,000 nodes with zero bytes allocated per frame (7, 9).

## 13. Where helder does better

Against r3f and drei:

1. **Checked when compiling, not at run time.** Prop names, prop types,
   slots, handlers and model names are all checked when compiling, in Haxe
   and TSX alike. r3f resolves `rotation-x` and `attach="material-0"` by
   string at run time, types `args` loosely, and needs gltfjsx to type a
   model.
2. **No re-render, no reconcile.** A change is one typed store. r3f's
   pitfalls page, zustand's transient updates and the advice to mutate in
   `useFrame` all exist to avoid React re-rendering; in helder there is
   nothing to avoid.
3. **Safe lifetimes by construction.** There is no `dispose={null}` to
   forget, and a shared model is never freed by one of its users.
4. **On demand without `invalidate()` in user code.** Bindings, `onFrame`,
   controls, animations and assets invalidate their own world. r3f's
   default is `always`, and its `demand` mode needs `invalidate()` after
   every direct mutation.
5. **Instancing for free.** Meshes sharing a geometry and material are one
   draw with no `<Instances>`. Flat `<instances>` with per-instance events
   cover the next order of magnitude, with no component per instance.
6. **One gesture arena.** Taps, drags, gizmos and orbit controls compete
   in one arena, so a drag on a draggable mesh does not also orbit the
   camera.
7. **Ui in the world is the same ui.** `<Ui>` (and later `<Ui transform>`)
   is helder.ui's layout, text and events drawn on the GPU. drei's `<Html>`
   is the DOM over a canvas, and `transform` mode can look blurry.
8. **Only what is used links.** It is measured per tag family, natively and
   as wasm32. A drei import is a bundler's tree-shaking at best.
9. **Shaders are compiled at build time**, so there is no `<Preload>` to
   warm materials.

Against solid-three, which shares the signals model:

1. **Production status and the rest of the engine.** helder's markup sits
   on a renderer, physics, input, assets and a gesture arena that are
   tested together on every target. solid-three is "not yet ready for
   production use".
2. **Typed rather than reflective.** solid-three keeps r3f's run-time
   object model (`args`, dashed props, objects made by name). helder
   compiles each prop to its own setter, with struct values unboxed.
3. **A flat world.** helder's nodes are handles into flat arrays, so 10,000
   nodes are 10,000 slots, not 10,000 three.js objects with their own
   matrices.
4. **Async the graph's own way.** `<Loading>` holds a pending model inside
   the graph, with no torn frames, where Solid's Suspense goes through
   resources.

## Sources

Fetched on 2026-11-15.

1. react-three-fiber, Objects, properties and constructor arguments (v9.8.2): https://r3f.docs.pmnd.rs/api/objects
2. react-three-fiber, Events: https://r3f.docs.pmnd.rs/api/events
3. react-three-fiber, Performance pitfalls: https://r3f.docs.pmnd.rs/advanced/pitfalls
4. react-three-fiber, Scaling performance: https://r3f.docs.pmnd.rs/advanced/scaling-performance
5. react-three-fiber, Hooks: https://r3f.docs.pmnd.rs/api/hooks
6. react-three-fiber, v9 migration guide: https://r3f.docs.pmnd.rs/tutorials/v9-migration-guide
7. react-three-fiber, Canvas: https://r3f.docs.pmnd.rs/api/canvas
8. react-three-fiber, Additional exports (createPortal, invalidate, advance): https://r3f.docs.pmnd.rs/api/additional-exports
9. react-three-fiber, TypeScript: https://r3f.docs.pmnd.rs/api/typescript
10. react-three-fiber releases (v9.8.2; v10.0.0-alpha "Going WebGPU First"): https://github.com/pmndrs/react-three-fiber/releases
11. drei, Environment (v10.7.9): https://drei.docs.pmnd.rs/staging/environment
12. drei, AccumulativeShadows: https://drei.docs.pmnd.rs/staging/accumulative-shadows
13. drei, ContactShadows: https://drei.docs.pmnd.rs/staging/contact-shadows
14. drei, Instances: https://drei.docs.pmnd.rs/performances/instances
15. drei, Merged: https://drei.docs.pmnd.rs/performances/merged
16. drei, Bounds: https://drei.docs.pmnd.rs/staging/bounds
17. drei, Html: https://drei.docs.pmnd.rs/misc/html
18. drei, useGLTF: https://drei.docs.pmnd.rs/loaders/gltf-use-gltf
19. drei, Text: https://drei.docs.pmnd.rs/abstractions/text
20. drei, KeyboardControls: https://drei.docs.pmnd.rs/controls/keyboard-controls
21. drei, PerformanceMonitor: https://drei.docs.pmnd.rs/performances/performance-monitor
22. drei, Detailed: https://drei.docs.pmnd.rs/performances/detailed
23. drei, Bvh: https://drei.docs.pmnd.rs/performances/bvh
24. drei, AdaptiveDpr: https://drei.docs.pmnd.rs/performances/adaptive-dpr
25. drei, useProgress: https://drei.docs.pmnd.rs/loaders/progress-use-progress
26. drei, Preload: https://drei.docs.pmnd.rs/performances/preload
27. drei, CameraControls: https://drei.docs.pmnd.rs/controls/camera-controls
28. gltfjsx: https://github.com/pmndrs/gltfjsx
29. zustand: https://github.com/pmndrs/zustand
30. leva: https://github.com/pmndrs/leva
31. @react-three/rapier: https://github.com/pmndrs/react-three-rapier
32. uikit, introduction: https://pmndrs.github.io/uikit/docs/getting-started/introduction
33. @react-three/postprocessing: https://github.com/pmndrs/react-postprocessing
34. @react-three/a11y: https://github.com/pmndrs/react-three-a11y
35. react-three-offscreen: https://github.com/pmndrs/react-three-offscreen
36. Threlte, <T>: https://threlte.xyz/docs/reference/core/t
37. Threlte, useTask: https://threlte.xyz/docs/reference/core/use-task
38. Threlte, Scheduling tasks: https://threlte.xyz/docs/learn/basics/scheduling-tasks
39. Threlte, Render modes: https://threlte.xyz/docs/learn/basics/render-modes
40. Threlte, interactivity: https://threlte.xyz/docs/reference/extras/interactivity
41. Threlte, Plugins: https://threlte.xyz/docs/learn/advanced/plugins
42. Threlte extras, InstancedMesh: https://threlte.xyz/docs/reference/extras/instanced-mesh
43. Threlte extras, useGltf: https://threlte.xyz/docs/reference/extras/use-gltf
44. Threlte, migration guides (8): https://threlte.xyz/docs/learn/advanced/migration-guides
45. TresJS, installation (v5.11.0): https://docs.tresjs.org/getting-started/installation
46. TresJS, useLoop: https://docs.tresjs.org/api/composables/use-loop
47. TresJS, performance and render modes: https://docs.tresjs.org/api/advanced/performance
48. Cientos: https://cientos.tresjs.org/
49. solid-three: https://github.com/solidjs-community/solid-three
50. solid-three, useFrame: https://solidjs-community.github.io/solid-three/api/hooks/use-frame
51. solid-three, Props and children: https://solidjs-community.github.io/solid-three/tour/02-props-and-children
52. solid-three on npm: https://registry.npmjs.org/solid-three
53. A-Frame, Entity-component-system: https://aframe.io/docs/1.7.0/introduction/entity-component-system.html
54. A-Frame, Component (1.8.0): https://aframe.io/docs/1.8.0/core/component.html
55. A-Frame, Mixins: https://aframe.io/docs/1.8.0/core/mixins.html
56. A-Frame, Best practices: https://aframe.io/docs/1.8.0/introduction/best-practices.html
57. A-Frame, Asset management system: https://aframe.io/docs/1.7.0/core/asset-management-system.html
58. Babylon.js, GUI: https://doc.babylonjs.com/features/featuresDeepDive/gui/gui
59. Babylon.js, 3D GUI: https://doc.babylonjs.com/features/featuresDeepDive/gui/gui3D
60. Announcing Babylon.js 9.0: https://blogs.windows.com/windowsdeveloper/2026/03/26/announcing-babylon-js-9-0/
61. react-babylonjs: https://github.com/brianzinn/react-babylonjs
62. Godot, TSCN file format: https://docs.godotengine.org/en/stable/engine_details/file_formats/tscn.html
63. Godot, Creating instances: https://docs.godotengine.org/en/stable/getting_started/step_by_step/instancing.html
64. Godot, Import configuration (inherited scenes): https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html
65. Godot, Node (editable instances): https://docs.godotengine.org/en/stable/classes/class_node.html
66. Godot, GDScript exported properties: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_exports.html
67. Godot, Using signals: https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html
68. Bevy 0.19 (BSN): https://bevy.org/news/bevy-0-19/
69. Bevy 0.20: https://bevy.org/news/bevy-0-20/
70. Bevy, 0.18 to 0.19 migration guide: https://bevy.org/learn/migration-guides/0-18-to-0-19/
71. Bevy 0.15 (required components): https://bevy.org/news/bevy-0-15/
72. cart, Bevy's Next Generation Scene/UI System: https://github.com/bevyengine/bevy/discussions/14437
73. Next Generation Scenes: core scene system, bsn! macro, templates (#23413): https://github.com/bevyengine/bevy/pull/23413
74. Unity 6.6, Nested prefabs: https://docs.unity.com/en-us/engine/current/manual/working-with-gameobjects/prefabs/nested
75. Unity 6.6, Prefab variants: https://docs.unity.com/en-us/engine/current/manual/working-with-gameobjects/prefabs/prefab-variants
76. Unity 6.6, Instance overrides: https://docs.unity.com/en-us/engine/current/manual/working-with-gameobjects/prefabs/override/prefab-instance-overrides
77. Unity Entities 1.3, Baking overview: https://docs.unity3d.com/Packages/com.unity.entities@1.3/manual/baking-overview.html
