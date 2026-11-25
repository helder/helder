// helder.scene.view for TypeScript programs (helder.typescript): a 3D scene
// in a ui's layout, all markup: <Scene> and, inside it, the scene's own
// elements (node, mesh, the geometry and material tags, light, camera,
// lines, text3d...: SceneRenderer's), <OrbitControls>, <Ui> and the post
// chain's <Effects> with its effects.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Camera, Renderer, ToneMap, World} from "../../scene/runtime";
import type {Vec3, Vec4} from "helder/gfx";
import type {Node, UiView} from "helder/ui";
import type {Read} from "helder/view";

declare const __haxe: {Scene: "helder.scene.view.SceneTags.Scene", OrbitControls: "helder.scene.view.SceneTags.OrbitControls", Ui: "helder.scene.view.SceneTags.Ui", Effects: "helder.scene.view.EffectTags.Effects", Ssao: "helder.scene.view.EffectTags.Ssao", Outline: "helder.scene.view.EffectTags.Outline", Fxaa: "helder.scene.view.EffectTags.Fxaa", __module: "helder.scene.view.TypeScript"};

// helder.scene's markup (helder.view.ViewOf): a component returning one is
// pinned to the scene, a children prop typed so makes its content scene nodes
export type SceneView = unknown;

// a box (ui's: flexGrow, width, height, style...) of world as camera sees it
export declare function Scene(props: { world?: World; camera?: Camera; flexGrow?: number; width?: Read<any>; height?: Read<any>; style?: any; animate?: boolean; antialias?: boolean; scale?: Read<number>; density?: Read<number>; hdr?: boolean; pick?: unknown; setup?: (arg0: Renderer) => void; ref?: (arg0: unknown) => void; children?: SceneView }): Node;
// the <Scene>'s camera orbiting target, driven by the pointers over its
// box (OrbitControls: one finger or the left button turns it, two
// pinch and move it, the right button moves it, the wheel zooms); its
// props are OrbitControls' (a target bound to a signal follows it)
export declare function OrbitControls(props: { camera?: Camera; target?: any; minDistance?: number; maxDistance?: number; minPitch?: number; maxPitch?: number; rotateSpeed?: number; zoomSpeed?: number; panSpeed?: number; damping?: number; enableRotate?: boolean; enableZoom?: boolean; enablePan?: boolean; enableTwist?: boolean; ref?: (arg0: unknown) => void }): unknown;
// ui inside a scene: its children ui's markup, over the <Scene>'s box at
// its node's place (centred; position, as any node's)
export declare function Ui(props: { position?: Vec3; children?: UiView }): unknown;

// the chain's own values; its children the effects
export declare function Effects(props: { bloom?: Read<number>; toneMap?: ToneMap; exposure?: Read<number>; saturation?: Read<number>; contrast?: Read<number>; vignette?: Read<number>; grain?: Read<number>; levels?: number; base?: number; children?: SceneView }): unknown;
// screen-space ambient occlusion (helder.scene.render.Ssao: GTAO)
export declare function Ssao(props: { radius?: Read<number>; intensity?: Read<number>; samples?: number; slices?: number; halfRes?: boolean }): unknown;
// the selection's outlines (helder.scene.render.Outline): group 1's
// width and colour; nodes selected by their outline prop (<node
// outline={1}>) or Outline.select
export declare function Outline(props: { width?: Read<number>; color?: Read<Vec4> }): unknown;
// FXAA in the composite (post.antialias Fxaa)
export declare function Fxaa(props: {}): unknown;

export {};
