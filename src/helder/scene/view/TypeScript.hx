package helder.scene.view;

// helder.scene.view for TypeScript programs (helder.typescript): a 3D scene
// in a ui's layout, all markup: <Scene> and, inside it, the scene's own
// elements (node, mesh, the geometry and material tags, light, camera,
// lines, text3d...: SceneRenderer's), <OrbitControls>, <Ui> and the post
// chain's <Effects> with its effects.
@:typescript("helder/scene/view")
@:typescript.functions(Scene = helder.scene.view.SceneTags.Scene, OrbitControls = helder.scene.view.SceneTags.OrbitControls, Ui = helder.scene.view.SceneTags.Ui,
	Effects = helder.scene.view.EffectTags.Effects, Ssao = helder.scene.view.EffectTags.Ssao, Outline = helder.scene.view.EffectTags.Outline,
	Fxaa = helder.scene.view.EffectTags.Fxaa)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
