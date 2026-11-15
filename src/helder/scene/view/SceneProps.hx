package helder.scene.view;

import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.math.Curve3;
import helder.scene.math.Quat;
import helder.scene.render.Geometry;
import helder.scene.render.Material;

// The props of SceneRenderer's elements (@:props: markup checks an
// attribute's name against its element's when compiling): the geometry and
// material tags' are the options of Geometry's and Material's factories, so
// a tag is its factory's options by name (<cylinderGeometry radiusTop>,
// <toonMaterial steps>); the nodes' are a node's (position, rotation,
// scale, name, visible) and their component's.
typedef SceneProps = {
	node:NodeProps,
	mesh:MeshProps,
	instances:InstancesProps,
	sprites:SpritesProps,
	light:LightProps,
	directionalLight:LightProps,
	pointLight:LightProps,
	spotLight:LightProps,
	hemisphereLight:HemisphereProps,
	camera:CameraProps,
	boxGeometry:BoxOptions,
	sphereGeometry:SphereOptions,
	cylinderGeometry:CylinderOptions,
	coneGeometry:ConeOptions,
	capsuleGeometry:CapsuleOptions,
	torusGeometry:TorusOptions,
	torusKnotGeometry:TorusKnotOptions,
	ringGeometry:RingOptions,
	circleGeometry:CircleOptions,
	planeGeometry:PlaneOptions,
	latheGeometry:LatheProps,
	tubeGeometry:TubeProps,
	standardMaterial:MaterialOptions,
	lambertMaterial:MaterialOptions,
	phongMaterial:PhongOptions,
	toonMaterial:ToonOptions,
	unlitMaterial:MaterialOptions,
	matcapMaterial:MatcapOptions,
	normalMaterial:MaterialOptions,
	depthMaterial:DepthProps
}

// every node's
typedef NodeProps = {
	?name:String,
	?position:Vec3,
	?rotation:Quat,
	?scale:Vec3,
	?visible:Bool
}

// a mesh's: its geometry and material (shared: a geometry or material made
// in code), else its children's (<boxGeometry>, <toonMaterial>), else a
// shape made of shape, size and a standard material of color, metallic,
// roughness
typedef MeshProps = {
	> NodeProps,
	?geometry:helder.scene.render.VertexData,
	?material:Material,
	?shape:String,
	?size:Float,
	?color:Vec4,
	?metallic:Float,
	?roughness:Float
}

typedef InstancesProps = {
	> NodeProps,
	?of:helder.scene.render.InstancedMesh
}

// <sprites of={set} mode="axis"/>: mode spherical, axis or fixed
typedef SpritesProps = {
	> NodeProps,
	?of:helder.scene.render.Sprites,
	?mode:String
}

// a light's (light's kind: directional, point, spot, hemisphere; inner and
// outer a spot's cones, radians)
typedef LightProps = {
	> NodeProps,
	?kind:String,
	?color:Vec3,
	?intensity:Float,
	?range:Float,
	?inner:Float,
	?outer:Float
}

typedef HemisphereProps = {
	> NodeProps,
	?sky:Vec3,
	?ground:Vec3,
	?intensity:Float
}

typedef CameraProps = {
	> NodeProps,
	?fov:Float,
	?near:Float,
	?far:Float
}

typedef LatheProps = {
	> LatheOptions,
	?points:Array<Vec2>
}

typedef TubeProps = {
	> TubeOptions,
	?curve:Curve3
}

typedef DepthProps = {
	> MaterialOptions,
	?near:Float,
	?far:Float
}
