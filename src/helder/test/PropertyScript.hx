package helder.test;

import helder.test.Gen.array as genArray;
import helder.test.Gen.bool as genBool;
import helder.test.Gen.char as genChar;
import helder.test.Gen.float as genFloat;
import helder.test.Gen.int as genInt;
import helder.test.Property;

// helder/test's properties for TypeScript (its index.ts: Gen, property,
// stateful, assume): the generators of helder.test.Gen as functions of a
// case's Choices, and a property's run through Property. A TypeScript body
// or step returns null when it passed, "" when it stopped (its failure
// recorded), else its error's text; one that caught a Rejected or an
// Overran (assume, a filter, a sequence run out) has it thrown again here.
// Options a property doesn't set are null.
class PropertyScript {
	public static function int(min:Int, max:Int):Choices->Int
		return genInt(min, max);

	public static function float(min:Float, max:Float):Choices->Float
		return genFloat(min, max);

	public static function bool():Choices->Bool
		return genBool();

	public static function char(nul:Bool):Choices->String
		return genChar(nul);

	// an index into n items, shrinking to 0 (pick, oneOf)
	public static function index(n:Int):Choices->Int
		return c -> c.choice(n - 1);

	// min to max items drawn by item, each one given to add (an array's)
	public static function items(c:Choices, item:Choices->Dynamic, min:Int, max:Int, add:Dynamic->Void)
		for (v in c.draw(genArray(item, min, max))) add(v);

	// (a TypeScript catch took a Rejected or an Overran)
	public static function pending():Bool
		return Property.control != null;

	public static function reject():Void
		throw Property.control = new Choices.Rejected();

	public static function property(gen:Choices->Dynamic, body:Dynamic->Null<String>, show:Dynamic->String, cases:Null<Int>,
			seconds:Null<Float>, seed:Null<Int>, replay:Null<String>, at:String)
		Property.check(gen, v -> done(body(v)), show, {cases: cases, seconds: seconds, seed: seed, replay: replay}, Script.pos(at));

	// a machine of count steps, its system kept by the TypeScript side
	// (a value through Dynamic is a copy): step i's name, its run (its result
	// as a body's), whether it can run
	public static function stateful(setup:() -> Void, count:Int, name:Int->String, run:(Int, Choices) -> Null<String>, when:Int->Bool,
			check:() -> Null<String>, teardown:() -> Void, show:Dynamic->String, cases:Null<Int>, seconds:Null<Float>, seed:Null<Int>,
			replay:Null<String>, steps:Null<Int>, at:String) {
		var m:Machine<Int> = {
			setup: () -> {
				setup();
				0;
			},
			steps: [for (i in 0...count) {name: name(i), run: (_, c) -> done(run(i, c)), when: _ -> when(i)}],
			check: _ -> done(check()),
			teardown: _ -> teardown()
		};
		Property.stateful(m, {cases: cases, seconds: seconds, seed: seed, replay: replay, steps: steps}, Script.pos(at), show);
	}

	static function done(result:Null<String>) {
		if (result == null) return;
		if (Property.control != null) throw Property.control;
		if (result != "") Runner.capture?.push("error: " + result);
		throw new Runner.Stop("stopped");
	}
}
