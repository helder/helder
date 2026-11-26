package helder.scene.render;

import helder.gfx.*;
import helder.math.Vec4;

// Depth of field, a PostProcess's (post.dof): a circle of confusion from
// the view buffers' depth (ViewBuffers, asked for by the chain), the
// scene's light gathered on a disc that wide at half the frame's size in
// linear light (before bloom and the curve: bright specks spread as
// discs), then mixed into the composite where the circle is wider than a
// texel. Two lenses:
//
//   post.dof = Dof.focus({distance: 6, aperture: 0.02});   // sharp at 6 m, a thin lens's blur
//   post.dof = Dof.tiltShift({band: 0.2, falloff: 0.3, strength: 1});
//
// focus: sharp at distance (metres), the blur growing as a thin lens's to
// aperture at infinity (a share of the frame's height). tiltShift, a
// diorama's: sharp within band of the focus depth (a share of it: 0.2,
// within 20% nearer or farther), the blur growing past it to strength
// times radius over falloff more; its focus the depth under the frame at
// center (0 the top, 1 the bottom; the screen's centre by default), or
// distance when given. A world's depth, not the screen's band: a far
// island inside the band is blurred, as a lens would. Its target is
// RGBA16F, half the frame's size; nothing is allocated per frame. Its
// options alone: its pass is DofPass's, linked by a program that sets it
// on a chain (post.dof's setter).
class Dof {
	public var mode:DofMode;
	// focus: the distance in focus (metres); tiltShift: its focus (0: the
	// depth at center)
	public var distance:Float;
	// focus: the blur at infinity (a share of the frame's height)
	public var aperture:Float;
	// tiltShift: the depth kept sharp about the focus, and the depth past it
	// over which the blur reaches its most (shares of the focus depth)
	public var band:Float;
	public var falloff:Float;
	// tiltShift: how much of the radius the blur reaches (0 none, 1 all)
	public var strength:Float;
	// the most blur (a share of the frame's height)
	public var radius:Float;
	// tiltShift: where on the frame its focus is read (0 the top, 1 the bottom)
	public var center:Float;
	// the taps of the blur's disc (16 for phones, 24, 32)
	public var samples:Int;
	// the last frame's blur (RGBA16F, half the frame's size)
	public var texture(default, null):Null<Texture> = null;

	function new(mode:DofMode) {
		this.mode = mode;
		distance = 0;
		aperture = 0.02;
		band = 0.2;
		falloff = 0.3;
		strength = 1;
		radius = 0.012;
		center = 0.5;
		samples = 16;
	}

	// a lens focused at distance metres, aperture its blur at infinity (a
	// share of the frame's height), at most radius
	public static function focus(options:{distance:Float, ?aperture:Float, ?radius:Float, ?samples:Int}):Dof {
		var d = new Dof(Focus);
		d.distance = options.distance;
		if (options.aperture != null) d.aperture = options.aperture;
		d.radius = options.radius ?? Math.max(d.aperture, 0.012);
		if (options.samples != null) d.samples = options.samples;
		return d;
	}

	// a diorama's lens: sharp within band of the focus depth, blurred to
	// strength times radius past falloff more
	public static function tiltShift(options:{?band:Float, ?falloff:Float, ?strength:Float, ?radius:Float, ?center:Float, ?distance:Float, ?samples:Int}):Dof {
		var d = new Dof(TiltShift);
		if (options.band != null) d.band = options.band;
		if (options.falloff != null) d.falloff = options.falloff;
		if (options.strength != null) d.strength = options.strength;
		if (options.radius != null) d.radius = options.radius;
		if (options.center != null) d.center = options.center;
		if (options.distance != null) d.distance = options.distance;
		if (options.samples != null) d.samples = options.samples;
		return d;
	}

	// (the composite's and the blur's dof: PostShader's cocOf)
	@:allow(helder.scene.render) function params():Vec4
		return mode == Focus ? new Vec4(1, distance, aperture, radius) : new Vec4(2, band, Math.max(falloff, 0.0001), radius * Math.max(0, strength));

}
