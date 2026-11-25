package lanes;

import lanes.Tools.*;

using StringTools;

class Text {
	public static final LANES:Array<Lane> = [
		{name: "text", about: "helder.text's rasterizer and layout on Eval", run: text},
		{name: "system-text", about: "helder.text on the platform's own text stack", run: systemText},
		{name: "text-quality", about: "helder.text's engine against Core Text's sheets", run: textQuality},
		{name: "syntax", about: "helder.syntax reading every source file back byte for byte", run: syntaxLane},
		{name: "syntax-run", about: "helder.syntax's edits on the examples, built and run", run: syntaxRun}
	];

	static function text() {
		mkdirs("bin");
		interp(cps(["src", "tests/text", "tests/gfx"]), "TextTest", BLESS ? ["--bless"] : []);
	}

	// (Windows and macOS; a Windows target from Linux under Wine; macOS: a HEIC made by sips)
	static function systemText() {
		native('bin/text/$GFX_TARGET/SystemTextTest', cps(["src", "tests/text"]).concat(["-main", "SystemTextTest"]), GFX_TARGET);
		var exe = exePath('bin/text/$GFX_TARGET/SystemTextTest', GFX_TARGET), env = ["HELDER_TEXT_ENGINE" => "system"];
		if (GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-")) {
			env.set("HELDER_UNDER_WINE", "1");
			run("wine", [exe], env);
		} else run(exe, [], env);
		// (on a Mac: CoreText's sheets for the text-quality lane, bin/text/coretext: tests/text/coretext/sheets is a copy)
		if (GFX_TARGET.startsWith("macos-") && HOST.startsWith("macos-")) {
			native('bin/text/$GFX_TARGET/TextQuality', cps(["src", "tests/text"]).concat(["-main", "TextQuality"]), GFX_TARGET);
			run(exePath('bin/text/$GFX_TARGET/TextQuality', GFX_TARGET), ["reference", "bin/text/coretext"]);
		}
	}

	// (the references: tests/text/coretext/sheets, CoreText's, drawn by the system-text lane on a Mac)
	static function textQuality() {
		native("bin/text-quality/TextQuality", cps(["src", "tests/text"]).concat(["-main", "TextQuality"]), HOST);
		run(exePath("bin/text-quality/TextQuality", HOST), ["compare", "tests/text/coretext/sheets", "bin/text-quality"]);
	}

	static function syntaxLane() {
		var cp = cps(["src", "tests/syntax"]);
		interp(cp, "Check");
		exe("bin/syntax/Check", cp.concat(["-main", "Check"]));
		run(exePath("bin/syntax/Check", HOST), []);
	}

	// (the examples edited, built and run headless, their trees checked)
	static function syntaxRun() {
		var h = helderCli(), o = "bin/syntax/run";
		var cp = cps(["src", "tests/syntax"]);
		interp(cp, "Examples", ["prepare", o]);
		for (app in ["todo", "ts-todo"])
			run(h, ["run", "--headless", '$o/$app', "--script", "tests/headless/todo.json", "--tree", '$o/$app-end.json']);
		run(h, ["run", "--headless", '$o/mail', "--tree", '$o/mail.json']);
		run(h, ["run", "--headless", '$o/guide/GuideScreen.hx', "--tree", '$o/guide.json']);
		run(h, ["run", "--headless", '$o/viewer', "--script", "tests/headless/viewer.json", "--size", "480x360", "--tree", '$o/viewer-end.json']);
		run(h, ["test", '$o/ts-todo-story', "--target", "host"]);
		interp(cp, "Examples", ["check", o]);
	}
}
