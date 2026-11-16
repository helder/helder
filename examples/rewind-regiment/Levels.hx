import Sim.*;

// The levels: where each side's squads stand (kind, rows by columns, their
// middle), the props (blue's: the player's to fire, once each; red's: fired
// by themselves at their step), the setting (only looks) and a hint. Every
// level is lost if nothing is done, and won by more than one single order
// (Solve.hx checks: it plays out every single order and counts the wins).
// The field: x from -5 (left) to 5, z from -7.5 (red's back) to 7.5
// (blue's); blue stands at z > 1, red at z < -1. An angle is the direction
// a prop faces, about y, from +z (0: towards blue, PI: towards red).
class Levels {
	public static final settings:Array<Setting> = [
		{name: "Bedroom", felt: 0x5E7D4E, floor: 0xB98A5E, plank: 0.62, grain: 0.5, accent: 0x7FA7D9, light: 0xFFE4C2, sky: 0xF3E6D3},
		{name: "Kitchen", felt: 0x8C857A, floor: 0xE9E4DA, plank: 0.0, grain: 0.0, accent: 0xE07A5F, light: 0xF4F6FF, sky: 0xEEF1EE},
		{name: "Study", felt: 0x9A845E, floor: 0x6B4A33, plank: 0.48, grain: 0.7, accent: 0x81B29A, light: 0xFFD2A0, sky: 0xE9DCCB},
		{name: "Playroom", felt: 0x6F9A7E, floor: 0xD8C7A1, plank: 0.0, grain: 0.0, accent: 0xF2CC8F, light: 0xFFF4E0, sky: 0xF6EEDD},
		{name: "Garden", felt: 0x7E9A4E, floor: 0x9C8A6A, plank: 0.0, grain: 0.0, accent: 0xB5835A, light: 0xFFF6E0, sky: 0xDCEBF2},
		{name: "Attic", felt: 0x6E7048, floor: 0x8C6E52, plank: 0.9, grain: 0.85, accent: 0xC9ADA7, light: 0xFFBE85, sky: 0xD9CBBE}
	];

	public static final levels:Array<Level> = [
		{
			name: "First Skirmish",
			hint: "Watch red's marble roll in and lose. Then drag the timeline back and roll yours first.",
			setting: 0,
			blue: [sq(GRUNT, 4, 4, -2.7, 3.4), sq(GRUNT, 4, 4, -0.9, 3.4), sq(GRUNT, 4, 4, 0.9, 3.4), sq(GRUNT, 4, 4, 2.7, 3.4)],
			red: [sq(GRUNT, 4, 4, -2.7, -3.4), sq(GRUNT, 4, 4, -0.9, -3.4), sq(GRUNT, 4, 4, 0.9, -3.4), sq(GRUNT, 4, 4, 2.7, -3.4), sq(GRUNT, 1, 2, 0, -5.0)],
			props: [marble(0, -4.3, 5.7, Math.PI), redMarble(4.3, -5.7, 0.2, 6)]
		},
		{
			name: "Domino Alley",
			hint: "Tip the dominoes just as red steps into their lane.",
			setting: 0,
			blue: [sq(GRUNT, 4, 4, -2.6, 3.6), sq(GRUNT, 4, 4, 0, 4.4), sq(GRUNT, 4, 4, 2.6, 3.6)],
			red: [sq(GRUNT, 4, 4, -2.4, -3.2), sq(GRUNT, 4, 4, 0, -3.6), sq(GRUNT, 4, 4, 2.4, -3.2), sq(GRUNT, 1, 6, 0, -5.4)],
			props: [dominoes(0, -2.5, 1.0, Math.PI, 13, -0.9, 0.3), marble(0, 4.3, 5.7, Math.PI)]
		},
		{
			name: "Sharpshooters",
			hint: "Riflemen shoot from afar but can't take a charge. Keep them covered.",
			setting: 0,
			blue: [sq(GRUNT, 3, 5, -1.6, 2.6), sq(RIFLE, 2, 5, 0.6, 4.6), sq(GRUNT, 3, 4, 3.0, 2.8)],
			red: [sq(GRUNT, 4, 4, -3.0, -3.2), sq(GRUNT, 3, 4, -0.8, -3.0), sq(GRUNT, 3, 4, 1.4, -3.2), sq(RIFLE, 2, 4, 3.4, -5.0)],
			props: [jack(0, -0.4, -0.2), marble(0, -4.3, 5.7, Math.PI)]
		},
		{
			name: "Last Train Home",
			hint: "Wind up the train. Timing is everything.",
			setting: 1,
			blue: [sq(GRUNT, 4, 4, -2.4, 3.4), sq(RIFLE, 2, 4, 0, 5.0), sq(GRUNT, 4, 4, 2.4, 3.4)],
			red: [sq(GRUNT, 3, 4, -3.0, -4.4), sq(GRUNT, 3, 4, -1.0, -4.6), sq(GRUNT, 3, 4, 1.0, -4.6), sq(GRUNT, 3, 4, 3.0, -4.4), sq(RIFLE, 1, 4, 0, -6.4)],
			props: [train(0, -3.5, -1.6, Math.PI / 2, 8.0, 0, -0.4), tower(0, 4.4, 1.8, 5)]
		},
		{
			name: "Tin Giant",
			hint: "A wind-up tank shrugs off soldiers. Find something heavier.",
			setting: 1,
			blue: [sq(GRUNT, 3, 4, -2.6, 3.2), sq(RIFLE, 2, 5, 0, 4.8), sq(GRUNT, 3, 4, 2.6, 3.2)],
			red: [sq(TANK, 1, 1, 0, -3.2), sq(GRUNT, 4, 4, -2.6, -3.6), sq(GRUNT, 4, 4, 2.6, -3.6), sq(RIFLE, 2, 5, 0, -5.6)],
			props: [catapult(0, -4.2, 5.4, Math.PI), dominoes(0, 4.4, 1.2, Math.PI, 12, 0.8, 0.4)]
		},
		{
			name: "Air Raid",
			hint: "Only riflemen can reach the helicopters. Or something flung very high.",
			setting: 1,
			blue: [sq(GRUNT, 4, 4, -2.6, 3.4), sq(RIFLE, 2, 4, 0, 5.2), sq(GRUNT, 4, 4, 2.6, 3.4)],
			red: [sq(HELI, 1, 3, 0, -4.6), sq(GRUNT, 4, 4, -2.0, -3.4), sq(GRUNT, 4, 4, 2.0, -3.4), sq(GRUNT, 3, 4, 0, -5.8), sq(GRUNT, 1, 4, 0, -6.9)],
			props: [jack(0, 0, 1.4), tower(0, -4.4, 1.6, 5), marble(0, 4.3, 5.7, Math.PI)]
		},
		{
			name: "Jeep Rush",
			hint: "Jeeps hit hard and fast. Make them crash into something.",
			setting: 2,
			blue: [sq(GRUNT, 4, 4, -2.4, 3.6), sq(GRUNT, 4, 4, 0, 3.0), sq(RIFLE, 2, 5, 2.4, 4.6)],
			red: [sq(JEEP, 1, 5, 0, -3.0), sq(GRUNT, 4, 5, -2.6, -4.2), sq(GRUNT, 4, 4, 2.6, -4.2), sq(RIFLE, 2, 5, 0, -5.6)],
			props: [train(0, 3.5, 0.6, -Math.PI / 2, 8.0, 0, 0.4), jack(0, -1.8, 1.2), catapult(0, 4.3, 6.0, Math.PI)]
		},
		{
			name: "Pincer",
			hint: "Red comes from both sides. You can't hold both.",
			setting: 2,
			blue: [sq(GRUNT, 4, 4, -1.0, 3.4), sq(GRUNT, 4, 4, 1.0, 3.4), sq(RIFLE, 2, 4, 0, 5.4), sq(TANK, 1, 1, 0, 1.9)],
			red: [sq(GRUNT, 4, 4, -3.8, -2.4), sq(GRUNT, 3, 5, -3.6, -4.6), sq(GRUNT, 4, 4, 3.8, -2.4), sq(GRUNT, 3, 5, 3.6, -4.6), sq(JEEP, 1, 3, 0, -5.4)],
			props: [dominoes(0, -4.2, 0.6, Math.PI, 12, -0.8, 0.35), dominoes(0, 4.2, 0.6, Math.PI, 12, 0.8, -0.35), redMarble(0, -6.2, 0, 7)]
		},
		{
			name: "Rolling Thunder",
			hint: "Red's train and marble both hit at once. Something has to give.",
			setting: 2,
			blue: [sq(GRUNT, 4, 4, -2.6, 3.4), sq(RIFLE, 2, 5, 0, 5.0), sq(GRUNT, 4, 4, 2.6, 3.4), sq(JEEP, 1, 2, 0, 2.6)],
			red: [sq(GRUNT, 4, 4, -2.6, -3.6), sq(TANK, 1, 1, 0, -3.2), sq(GRUNT, 4, 4, 2.6, -3.6), sq(HELI, 1, 1, 0, -6.0), sq(RIFLE, 2, 3, 0, -5.2)],
			props: [redTrain(-3.5, 2.0, Math.PI / 2, 8.0, 8, -0.3, 0), redMarble(-4.3, -5.7, -0.25, 5), catapult(0, 4.3, 6.0, Math.PI), tower(0, -4.4, 6.2, 4)]
		},
		{
			name: "The Grand Melee",
			hint: "Everything at once. One clever move can still turn it.",
			setting: 3,
			blue: [sq(GRUNT, 4, 4, -3.0, 3.4), sq(GRUNT, 4, 4, -1.0, 3.4), sq(GRUNT, 4, 4, 1.0, 3.4), sq(RIFLE, 2, 5, 3.2, 4.8), sq(TANK, 1, 1, -1.0, 5.4)],
			red: [sq(GRUNT, 3, 4, -3.2, -3.0), sq(GRUNT, 3, 4, -1.0, -3.0), sq(GRUNT, 3, 4, 1.2, -3.0), sq(TANK, 1, 1, 3.4, -3.0), sq(HELI, 1, 1, 0, -5.8),
				sq(RIFLE, 2, 3, -1.0, -5.4), sq(JEEP, 1, 3, 3.0, -5.6), sq(GRUNT, 4, 4, -3.4, -5.6)],
			props: [jack(0, 0, -0.4), dominoes(0, -4.4, 1.2, Math.PI, 12, -0.8, 0.4), marble(0, 4.3, 6.0, Math.PI), top(0, 2.4, 1.4), redMarble(-4.3, -6.0, 0.15, 9)]
		},
		{
			name: "Rocket Range",
			hint: "Red's bazookas lob rockets over their own lines. Get behind them.",
			setting: 3,
			blue: [sq(GRUNT, 4, 4, -2.6, 3.4), sq(GRUNT, 4, 4, 0, 3.4), sq(RIFLE, 2, 5, 2.6, 4.6)],
			red: [sq(GRUNT, 2, 4, -1.6, -2.4), sq(GRUNT, 2, 4, 1.6, -2.4), sq(BAZOOKA, 1, 4, -2.4, -5.6), sq(BAZOOKA, 1, 4, 2.4, -5.6)],
			props: [top(0, -4.2, 1.6), marble(0, 4.3, 5.7, Math.PI), catapult(0, -1.3, 6.4, Math.PI)]
		},
		{
			name: "Spin Cycle",
			hint: "A spinning top goes where it likes. Mostly.",
			setting: 3,
			blue: [sq(GRUNT, 4, 4, -2.4, 3.2), sq(BAZOOKA, 2, 4, 0, 5.0), sq(GRUNT, 4, 4, 2.4, 3.2)],
			red: [sq(TANK, 1, 1, -1.6, -3.0), sq(TANK, 1, 1, 1.6, -3.0), sq(GRUNT, 4, 4, -3.2, -4.6), sq(GRUNT, 4, 4, 3.2, -4.6), sq(GRUNT, 2, 4, 0, -5.4), sq(BAZOOKA, 2, 3, 0, -6.6)],
			props: [top(0, 0, 1.4), jack(0, -3.6, 0.8)]
		},
		{
			name: "Tin Men",
			hint: "Wind-up robots swing at everyone around them. Don't stand close.",
			setting: 4,
			blue: [sq(GRUNT, 4, 4, -2.6, 3.4), sq(RIFLE, 2, 5, 0, 5.0), sq(GRUNT, 4, 4, 2.6, 3.4)],
			red: [sq(ROBOT, 1, 4, 0, -3.0), sq(GRUNT, 4, 4, -3.0, -4.2), sq(GRUNT, 4, 4, 3.0, -4.2), sq(RIFLE, 2, 5, 0, -5.8)],
			props: [marble(0, -4.3, 5.7, Math.PI), dominoes(0, 3.0, 0.4, Math.PI, 12, 0.4, -0.55)]
		},
		{
			name: "Garden Party",
			hint: "Your own robots this time. Point them at the thick of it.",
			setting: 4,
			blue: [sq(ROBOT, 1, 3, 0, 2.6), sq(GRUNT, 3, 4, -2.8, 3.6), sq(GRUNT, 3, 4, 2.8, 3.6), sq(BAZOOKA, 1, 4, 0, 5.4)],
			red: [sq(GRUNT, 4, 4, -2.6, -3.2), sq(GRUNT, 4, 5, 0, -3.6), sq(GRUNT, 4, 4, 2.6, -3.2), sq(JEEP, 1, 3, 0, -5.6), sq(RIFLE, 1, 5, 0, -6.6)],
			props: [jack(0, 0, 0.6), catapult(0, 4.3, 6.0, Math.PI)]
		},
		{
			name: "Lawn Wars",
			hint: "Red's robots, red's helicopters, red's train. Your top, your tower.",
			setting: 4,
			blue: [sq(GRUNT, 4, 4, -2.8, 3.4), sq(RIFLE, 2, 5, 0, 5.0), sq(ROBOT, 1, 2, 2.8, 3.0), sq(GRUNT, 3, 4, 2.8, 4.4)],
			red: [sq(ROBOT, 1, 2, -1.6, -3.0), sq(HELI, 1, 2, 1.6, -5.2), sq(GRUNT, 4, 4, -3.0, -4.4), sq(GRUNT, 4, 4, 2.4, -3.4), sq(BAZOOKA, 1, 4, 0, -6.2), sq(RIFLE, 1, 4, -1.0, -5.6)],
			props: [redTrain(-3.5, 1.6, Math.PI / 2, 8.0, 9, -0.3, 0), top(0, -4.2, 6.0), tower(0, 4.4, 6.2, 5)]
		},
		{
			name: "Air and Iron",
			hint: "Helicopters above, a tank below. Choose your fight.",
			setting: 5,
			blue: [sq(GRUNT, 4, 4, -2.8, 3.4), sq(RIFLE, 2, 5, -0.6, 5.0), sq(BAZOOKA, 1, 3, 1.6, 5.2), sq(GRUNT, 3, 4, 3.0, 3.4)],
			red: [sq(HELI, 1, 3, -1.2, -5.0), sq(TANK, 1, 2, 1.8, -3.0), sq(GRUNT, 4, 4, -2.6, -3.4), sq(BAZOOKA, 2, 5, 0, -5.8), sq(GRUNT, 4, 4, 3.4, -4.4), sq(GRUNT, 2, 4, -2.6, -5.6)],
			props: [catapult(0, -4.3, 6.0, Math.PI), tower(0, 4.4, 1.7, 5), top(0, 0, 1.2)]
		},
		{
			name: "Final Offensive",
			hint: "Red throws everything it has. You have one move. Make it count.",
			setting: 5,
			blue: [sq(GRUNT, 4, 4, -3.2, 3.2), sq(GRUNT, 4, 4, -1.1, 3.2), sq(GRUNT, 4, 4, 1.1, 3.2), sq(RIFLE, 2, 5, 3.3, 4.6), sq(BAZOOKA, 2, 4, -1.1, 5.2)],
			red: [sq(GRUNT, 4, 4, -3.2, -3.0), sq(GRUNT, 4, 4, -1.0, -3.0), sq(GRUNT, 4, 4, 1.2, -3.0), sq(TANK, 1, 1, 3.4, -3.0), sq(HELI, 1, 2, 0, -6.0),
				sq(BAZOOKA, 2, 4, -1.0, -5.4), sq(JEEP, 1, 5, 3.0, -5.6), sq(TANK, 1, 1, -3.4, -6.2), sq(GRUNT, 2, 4, 1.2, -6.6)],
			props: [redTrain(3.5, -1.0, -Math.PI / 2, 8.0, 10, -0.3, 0), redTop(-4.2, -6.4, 0, 2, 6), jack(0, 0, 1.0), top(0, 4.3, 1.2), marble(0, -4.3, 6.0, Math.PI)]
		}
	];

	static function sq(kind:Int, rows:Int, cols:Int, x:Float, z:Float):SquadDef
		return {kind: kind, rows: rows, cols: cols, x: x, z: z};

	static function base(type:Int, team:Int, x:Float, z:Float, angle:Float):PropDef
		return {type: type, team: team, x: x, z: z, angle: angle, count: 0, length: 0, bend: 0, wave: 0, at: -1, tx: 0, tz: 0};

	// a marble on a stack of books, its ramp down along angle
	static function marble(team:Int, x:Float, z:Float, angle:Float):PropDef
		return base(MARBLE, team, x, z, angle);

	// red's marble, rolled down its ramp (angle: towards blue, 0) at second at
	static function redMarble(x:Float, z:Float, angle:Float, at:Float):PropDef {
		var p = base(MARBLE, 1, x, z, angle);
		p.at = Std.int(at * 60);
		return p;
	}

	// count dominoes from x, z along angle, 0.42 apart, falling along it
	static function dominoes(team:Int, x:Float, z:Float, angle:Float, count:Int, bend = 0.0, wave = 0.0):PropDef {
		var p = base(DOMINO, team, x, z, angle);
		p.count = count;
		p.bend = bend;
		p.wave = wave;
		return p;
	}

	// a train at x, z running along angle for length
	static function train(team:Int, x:Float, z:Float, angle:Float, length:Float, bend = 0.0, wave = 0.0):PropDef {
		var p = base(TRAIN, team, x, z, angle);
		p.length = length;
		p.bend = bend;
		p.wave = wave;
		return p;
	}

	static function redTrain(x:Float, z:Float, angle:Float, length:Float, at:Float, bend = 0.0, wave = 0.0):PropDef {
		var p = train(1, x, z, angle, length, bend, wave);
		p.at = Std.int(at * 60);
		return p;
	}

	static function jack(team:Int, x:Float, z:Float):PropDef
		return base(JACK, team, x, z, 0);

	static function tower(team:Int, x:Float, z:Float, count:Int):PropDef {
		var p = base(TOWER, team, x, z, 0.3);
		p.count = count;
		return p;
	}

	// a spinning top at x, z (set going at a point)
	static function top(team:Int, x:Float, z:Float):PropDef
		return base(TOP, team, x, z, 0);

	// red's spinning top, set going at tx, tz at second at
	static function redTop(x:Float, z:Float, tx:Float, tz:Float, at:Float):PropDef {
		var p = base(TOP, 1, x, z, 0);
		p.tx = tx;
		p.tz = tz;
		p.at = Std.int(at * 60);
		return p;
	}

	// a ruler catapult at x, z flinging its eraser along angle (it lands where tapped)
	static function catapult(team:Int, x:Float, z:Float, angle:Float):PropDef
		return base(CATAPULT, team, x, z, angle);
}

typedef Level = {
	name:String,
	hint:String,
	setting:Int,
	blue:Array<SquadDef>,
	red:Array<SquadDef>,
	props:Array<PropDef>
}

typedef SquadDef = {
	kind:Int,
	rows:Int,
	cols:Int,
	x:Float,
	z:Float
}

typedef PropDef = {
	type:Int,
	team:Int,
	x:Float,
	z:Float,
	angle:Float,
	count:Int,
	length:Float,
	// (dominoes and trains: their path's turn from start to end, radians,
	// left positive; and an S's sway, radians either way)
	bend:Float,
	wave:Float,
	// red's: the step it fires, and where (a marble rolls down its ramp)
	at:Int,
	tx:Float,
	tz:Float
}

typedef Setting = {
	name:String,
	felt:Int,
	floor:Int,
	plank:Float,
	grain:Float,
	accent:Int,
	light:Int,
	sky:Int
}
