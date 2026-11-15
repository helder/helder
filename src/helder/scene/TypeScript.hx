package helder.scene;

// helder.scene for TypeScript programs (helder.typescript): what
// helder/scene (src/helder/scene/index.ts, with its Node, pbr and material)
// exports of helder's Haxe classes. A World of nodes (Node: helder/scene's
// class over a node's handle, its members Script's), cameras, lights,
// meshes (Shapes, Geometry's shapes and Curve3, MeshRenderer, InstancedMesh,
// Sprites) and materials (Material's factories: toon, lambert, unlit...), glTF models (Model,
// helder/asset's model(path) loads one; GltfScene), the renderer and its
// post chain (PostProcess: its effects Ssao, Dof, Outline, Lut; the view
// buffers they read, ViewBuffers), input
// actions (InputMap, Bindings), a fixed simulation step, and what a scene is
// drawn with: a window, its device (or a headless one), the app's loop. A
// program imports helder/scene, not this module.
@:typescript("helder/scene/runtime", "runtime.d.ts")
@:typescript.classes(helder.scene.World, helder.scene.Camera, helder.scene.render.Light, helder.scene.render.Renderer, helder.scene.render.Shadows, helder.scene.render.Fog, helder.scene.render.Material,
	helder.scene.render.MeshRenderer, helder.scene.render.Shapes, helder.scene.render.Geometry, helder.scene.render.VertexData, helder.scene.math.Curve3,
	helder.scene.render.InstancedMesh, helder.scene.render.Sprites, helder.scene.render.Model, helder.scene.render.MaterialShader, helder.scene.render.PostProcess,
	helder.scene.render.Ssao, helder.scene.render.Dof, helder.scene.render.Outline, helder.scene.render.Lut, helder.scene.render.ViewBuffers, helder.scene.input.InputMap,
	helder.scene.input.Bindings, helder.scene.FixedStep, helder.gfx.Device, helder.os.Surface, helder.os.Window, helder.os.App, helder.os.Event, helder.scene.Script)
@:typescript.types(helder.scene.render.Mesh, helder.gfx.Encoder, helder.os.Event.EventKind, helder.scene.input.Binding, helder.gfx.Feature,
	helder.scene.render.PostProcess.ToneMap, helder.scene.render.PostProcess.Antialias, helder.scene.render.Dof.DofMode)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
