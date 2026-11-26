package helder.scene.view;

import helder.math.Vec2;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.scene.math.Curve3;
import helder.math.Quat;
import helder.scene.render.Geometry;
import helder.scene.render.Material;

// The props of SceneRenderer's elements (@:props: markup checks an
// attribute's name against its element's when compiling): the geometry and
// material tags' are the options of Geometry's and Material's factories, so
// a tag is its factory's options by name (<cylinderGeometry radiusTop>,
// <toonMaterial steps>); the nodes' are a node's (position, rotation,
// scale, name, visible, outline) and their component's.
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
	depthMaterial:DepthProps,
	lines:LinesProps,
	text3d:Text3DProps,
	axesHelper:AxesHelperProps,
	gridHelper:GridHelperProps,
	boundsHelper:HelperProps,
	lightHelper:HelperProps,
	cameraHelper:CameraHelperProps,
	skeletonHelper:HelperProps,
	lod:LodProps
}

// <lines of={path}/>: the lines (made by the program, its points its own),
// their width and dashes' offset
typedef LinesProps = {
	> NodeProps,
	?of:helder.scene.render.Lines,
	?width:Float,
	?dashOffset:Float
}

// <text3d font={face} text={score} size={0.3} billboard/>, or of={label}
// (Text3D's options)
typedef Text3DProps = {
	> NodeProps,
	?of:helder.scene.render.Text3D,
	?font:helder.text.FontFile,
	?text:String,
	?size:Float,
	?depth:Float,
	?bevelSize:Float,
	?align:Float,
	?color:Vec4,
	?lit:Bool,
	?billboard:Bool,
	?castShadows:Bool
}

typedef AxesHelperProps = {
	> NodeProps,
	?size:Float
}

// (GridHelper's options)
typedef GridHelperProps = {
	> NodeProps,
	?size:Float,
	?divisions:Int,
	?fade:Float,
	?color:Vec4,
	?majorColor:Vec4
}

// a helper of the node it is in: its colour (0xRRGGBB)
typedef HelperProps = {
	> NodeProps,
	?color:Int
}

typedef CameraHelperProps = {
	> HelperProps,
	?aspect:Float
}

// every node's
typedef NodeProps = {
	?name:String,
	?position:Vec3,
	?rotation:Quat,
	?scale:Vec3,
	?visible:Bool,
	// its selection group (0: none; post.outline draws it: Outline.select)
	?outline:Int
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
// outer a spot's cones, radians; castShadows and its shadow's size, bias,
// normal offset, radius and strength: Light.castShadows, Light.shadow)
typedef LightProps = {
	> NodeProps,
	?kind:String,
	?color:Vec3,
	?intensity:Float,
	?range:Float,
	?inner:Float,
	?outer:Float,
	?castShadows:Bool,
	?shadowSize:Int,
	?shadowBias:Float,
	?shadowNormalBias:Float,
	?shadowRadius:Float,
	?shadowStrength:Float
}

// <lod levels={[{mesh: hi, until: 0.15}, {mesh: lo}]}/>: a node drawn at
// its levels of detail (Lod), held within hysteresis; begin and end a
// visible range (Lod.range: metres from the camera, it and what is under it)
typedef LodProps = {
	> NodeProps,
	?levels:Array<helder.scene.render.Lod.LodLevel>,
	?hysteresis:Float,
	?begin:Float,
	?end:Float
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
