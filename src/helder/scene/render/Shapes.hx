package helder.scene.render;

import helder.gfx.Device;

// Meshes made in code (no file): Geometry's shapes uploaded, each one
// primitive of a material. Shapes.of takes any Geometry (or VertexData);
// box, sphere, capsule and plane are the common ones at their usual sizes.
//
//   var post = Shapes.of(device, Geometry.cylinder({radiusTop: 0.1, radiusBottom: 0.1, height: 2, flat: true}), wood);
class Shapes {
	// a geometry (Geometry's, or any VertexData) as a mesh of one primitive
	public static function of(device:Device, geometry:VertexData, material:Material):Mesh {
		var m = new Mesh();
		m.addData(device, geometry, material);
		return m;
	}

	// a box of width, height and depth, centred, flat faces
	public static function box(device:Device, material:Material, w = 1.0, h = 1.0, d = 1.0):Mesh
		return of(device, Geometry.box({width: w, height: h, depth: d}), material);

	// a sphere of radius, segments around and rings from pole to pole
	public static function sphere(device:Device, material:Material, radius = 0.5, segments = 32, rings = 16):Mesh
		return of(device, Geometry.sphere({radius: radius, widthSegments: segments, heightSegments: rings}), material);

	// a capsule along y: the points within radius of the segment from -half
	// to half (physics' Capsule(radius, half)), segments around, rings in
	// each end's hemisphere
	public static function capsule(device:Device, material:Material, radius = 0.3, half = 0.6, segments = 24, rings = 8):Mesh
		return of(device, Geometry.capsule({radius: radius, height: 2 * half, capSegments: rings, radialSegments: segments}), material);

	// a square of size on y = 0, facing up (Geometry.plane turned from xy)
	public static function plane(device:Device, material:Material, size = 1.0):Mesh
		return of(device, Geometry.plane({width: size, height: size}).rotated(-Math.PI / 2, 0, 0), material);
}
