import haxe.Json;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The studio lane's checks (tests/lanes/Studio.hx: studio): helder studio (apps/studio)
// run headless on copies of examples/todo and examples/ts-todo by
// tests/studio/edit.json, its events (--events: JSON lines) and frames here:
// - every screen shown, a screen zoomed into, the title clicked and selected
//   (its node's box, its element in the source);
// - its colour changed in the inspector: one change, the value's span alone
//   (#3b82f6 to #ef4444), a live literal patched (no build), the program's
//   frame showing #ef4444 within 3 of the studio's frames;
// - a padding added (a build, the title 40 points taller), then undone (the
//   file as before it, built, the title as before);
// - tag="title" typed into the code view: built, the program's node tagged so;
// - the prompt bar's /tree answered by the studio's own tools;
// - the file at the end: the original with those two changes alone, every
//   edit's span applying to the text before it in order;
// - the overview, the zoomed and the selected frames against the goldens here.
// Then tests/studio/design (design files alone, tests/studio/design.json): its
// two frames drawn by the studio itself, nothing built; the first frame
// moved by its caption (canvas:at, snapped to the other's top); the title
// clicked and selected (its box, its element); its colour changed in the
// inspector (the value's span alone, the frame drawn again with it within 3
// frames), undone and redone (drawn so each time); the title resized by its
// handle (snapped to the frame's centre: width 171); a second node added to
// the selection with shift and taken from it; the title's layer dragged
// below the input row; both undone (the resize one entry); every edit's
// span applying in order, the file with the move and the colour alone.
// Then the free canvas (tests/studio/free.json, examples/todo): a click
// selects a frame, a story moved by its caption (its place made in
// canvas.helder), a double click enters a frame and selects its node,
// Escape twice; Play: the story run in the studio, a tap in it its
// program's (an item removed), Escape stops.
// Then a phone's sheets (tests/studio/phone.json, 390 by 844): opened from
// the bar, a frame picked in the files' (lowering it to peek), the handle
// dragged up to full and flung away, the code's at half.
// Then the sidebar's file browser (tests/studio/files.json, tests/studio/design
// with an image, a font and code in folders): the folders opened, the image
// in its viewer, the font in its specimen, code in the code view; the image
// dragged from the tree onto the Home frame (an <image src> of its path,
// its size the image's); a file dropped from the system on the assets
// folder's row copied into it.
// Then an empty folder in the studio's own shell (studioStart): the starter
// written, its one screen built and shown once the first prompt is answered.
// Then a story file changed under the studio (tests/Run.hx's studioStories:
// a copy of examples/ts-todo driven over MCP): its exports renamed, a story
// renamed and one added, the screens following them, built, the new one
// shown; a story file written on disk, its screen shown; a type error in
// app.tsx shown as the build's failure (its first error, app.tsx:line), then
// cleared by the fix.
// The measurements (cold start to the first frame, the project's screens
// all shown, an inspector's change to the program's frame) printed.
class Check {
	static var failed = 0;
	static var checks = 0;
	// (the goldens of the host the run is on: a headless studio draws the
	// system's chrome, its window buttons at macOS's start or Windows' and
	// Linux's end, ⌘ or Ctrl; Linux's, CI's, here, macOS's in macos/)
	static final here = switch Sys.systemName() {
		case "Mac": "tests/studio/macos";
		case "Windows": "tests/studio/windows";
		case _: "tests/studio";
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('studio: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var args = Sys.args();
		var dir = args[0], bless = args[1] == "--bless";
		var rows = [];
		for (app in ["todo", "ts-todo"]) {
			var source = app == "todo" ? "Todo.hx" : "app.tsx";
			rows.push(run(app, File.getContent('examples/$app/$source'), File.getContent('$dir/$app/$source'), events('$dir/$app.jsonl')));
			for (shot in ["overview", "zoomed", "selected"])
				image('$app-$shot.png', '$dir/$app-$shot.png', bless);
		}
		design(File.getContent("tests/studio/design/app.helder"), File.getContent('$dir/design/app.helder'), events('$dir/design.jsonl'));
		free(events('$dir/free.jsonl'), '$dir/free');
		phone(events('$dir/phone.jsonl'));
		files(File.getContent("tests/studio/design/app.helder"), File.getContent('$dir/files/app.helder'), events('$dir/files.jsonl'), '$dir/files');
		acp(events('$dir/acp.jsonl'));
		stories(events('$dir/stories.jsonl'));
		start(events('$dir/start.jsonl'));
		Sys.println("studio: | | cold start to first frame | open to all screens shown | inspector change to the program's frame |");
		for (r in rows) Sys.println('studio: | ${r.app} | ${r.first} ms | ${r.shown} ms | ${r.patch} ms (${r.frames} studio frame(s)) |');
		Sys.println('studio: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function events(path:String):Array<Dynamic>
		return [for (l in File.getContent(path).split("\n")) if (l.trim() != "") Json.parse(l)];

	static function run(app:String, original:String, final_:String, ev:Array<Dynamic>) {
		function all(name:String):Array<Dynamic>
			return ev.filter(e -> e.event == name);
		function first(name:String):Null<Dynamic>
			return all(name)[0];
		var ff:Dynamic = first("first-frame"), shown:Dynamic = first("all-shown");
		check('$app: the first frame', ff != null);
		check('$app: all 4 screens shown', shown != null && shown.screens == 4, Json.stringify(shown));
		var sel:Dynamic = first("selected");
		check('$app: the title selected (its box, its element)', sel != null && sel.tag == "text" && Json.stringify(sel.rect) == "[24,24,432,35]", Json.stringify(sel));
		var edits = all("edited");
		// (the colour: the inspector's first edit, the value's span alone)
		var color:Dynamic = edits[0];
		var at = original.indexOf('color="#3b82f6">todos') + 'color="'.length;
		check('$app: the colour\'s edit: #3b82f6\'s span alone', color != null && color.origin == "inspector" && color.changes.length == 1
			&& color.changes[0].start == at && color.changes[0].end == at + 7 && color.changes[0].text == "#ef4444", Json.stringify(color));
		var patched:Dynamic = first("patched");
		check('$app: the colour patched as a live literal (nothing built before it)', patched != null && ev.indexOf(patched) < ev.indexOf(first("building") ?? ev[ev.length - 1]),
			Json.stringify(patched));
		var p:Dynamic = first("patch-shown");
		check('$app: the program\'s frame shows #ef4444 within 3 studio frames', p != null && p.color == "#ef4444" && p.frames <= 3, Json.stringify(p));
		// (the selection's box after each build: padded, undone, typed)
		var boxes:Array<Dynamic> = all("selection");
		check('$app: the padding built: the title 75 points tall', Lambda.exists(boxes, (b:Dynamic) -> b.rect[3] == 75), Json.stringify([for (b in boxes) b.rect]));
		var padded:Dynamic = Lambda.find(edits, (e:Dynamic) -> e.origin == "inspector" && e.changes[0].text.indexOf("padding") >= 0);
		check('$app: the padding added after the colour, before the text', padded != null && padded.changes[0].start == at + 8, Json.stringify(padded));
		var undo:Dynamic = Lambda.find(edits, (e:Dynamic) -> e.origin == "undo");
		check('$app: the undo removes the padding alone', undo != null && undo.changes.length == 1 && undo.changes[0].text == ""
			&& undo.changes[0].start == at + 8 && undo.changes[0].end == at + 8 + " padding={20}".length, Json.stringify(undo));
		var afterUndo:Array<Dynamic> = boxes.filter((b:Dynamic) -> ev.indexOf(b) > ev.indexOf(undo));
		check('$app: undone: the title 35 points tall again', afterUndo.length > 0 && afterUndo[0].rect[3] == 35, Json.stringify(afterUndo.map((b:Dynamic) -> b.rect)));
		var built = all("built");
		check('$app: every build ok', built.length >= 3 && Lambda.foreach(built, (b:Dynamic) -> b.ok != false), Json.stringify(built));
		check('$app: typed tag="title": built, the node tagged title', boxes.length > 0 && boxes[boxes.length - 1].tag == "title",
			Json.stringify(boxes[boxes.length - 1]));
		var replied:Dynamic = first("replied");
		check('$app: the prompt bar\'s /tree answered by run.tree', replied != null && (replied.reply : String).startsWith("run.tree: {"), Json.stringify(replied));
		// (the edits replayed: each span on the text before it)
		var text = original;
		for (e in edits)
			for (c in (e.changes : Array<Dynamic>))
				text = text.substr(0, c.start) + c.text + text.substr(c.end);
		check('$app: the edits replayed give the file', text == final_);
		var expected = original.replace('<text font-size={28} font-weight={700} color="#3b82f6">todos',
			'<text tag="title" font-size={28} font-weight={700} color="#ef4444">todos');
		check('$app: the file: the original with the colour and the tag alone', final_ == expected);
		return {app: app, first: ff?.ms, shown: shown?.ms, patch: p?.ms, frames: p?.frames};
	}

	static function free(ev:Array<Dynamic>, dir:String) {
		function all(name:String):Array<Dynamic>
			return [for (e in ev) if (e.event == name) e];
		var focused:Array<String> = [for (e in all("focused")) e.screen ?? ""];
		check('free: a click selects a frame, the camera where it was', focused[0] == "Todo/Three items", focused.join(", "));
		var placed = all("placed")[0], dragged = all("dragged")[0];
		var canvas = try File.getContent('$dir/canvas.helder') catch (_:Dynamic) "";
		check('free: a story moved by its caption: its place made in canvas.helder',
			placed != null && placed.screen == "Todo/Done" && placed.file == "canvas.helder" && dragged != null && dragged.kind == "frame moved"
			&& ~/<Frame story="Todo.story.hx#done" canvas:at="-?[0-9]+ -?[0-9]+"\/>/.match(canvas), canvas);
		var entered = all("entered")[0], sel:Dynamic = Lambda.find(all("selected"), e -> e.screen == "Todo/Empty");
		check('free: a double click enters a frame and selects its node there', entered != null && entered.screen == "Todo/Empty" && sel != null && sel.tag == "scroll", Json.stringify(sel));
		var esc = focused.indexOf("");
		check('free: Escape leaves the frame, then selects nothing', esc > 0 && focused[esc - 1] == "Todo/Empty", focused.join(", "));
		var play = all("play")[0], stopped = all("stopped")[0];
		check('free: Play runs the selected story in the studio', play != null && play.kind == "story" && play.screen == "Todo/Three items" && play.target == "studio", Json.stringify(play));
		check('free: a tap in the player is the story\'s (Call Ana removed), Escape stops',
			stopped != null && (stopped.texts : Array<String>).contains("Buy milk") && !(stopped.texts : Array<String>).contains("Call Ana"), Json.stringify(stopped));
	}

	static function start(ev:Array<Dynamic>) {
		function all(name:String):Array<Dynamic>
			return [for (e in ev) if (e.event == name) e];
		check('start: an empty folder: the starter written', all("starter").length == 1, Json.stringify(all("starter")));
		var shown:Dynamic = all("all-shown")[0];
		check('start: its one screen built and shown', shown != null && shown.screens == 1, Json.stringify(shown));
		var replied:Dynamic = all("replied")[0];
		check('start: the first prompt answered (the blank sheet gone)', replied != null && (replied.reply : String).startsWith("run.tree: {"), Json.stringify(replied));
	}

	static function stories(ev:Array<Dynamic>) {
		function all(name:String):Array<Dynamic>
			return [for (e in ev) if (e.event == name) e];
		var read = all("stories");
		var first:Dynamic = read[0], extra:Dynamic = read[1];
		check('stories: the exports renamed, a story renamed and one added: the screens follow',
			first != null && (first.screens : Array<String>).join(", ") == "Todo/Empty, Todo/Three items, Todo/All done, Phone/Three items, Todo/One item",
			Json.stringify(first));
		var after = ev.filter(e -> e.event == "built" && ev.indexOf(e) > ev.indexOf(first));
		check('stories: then built, every source', after.length > 0 && after[0].ok == true, Json.stringify(after[0]));
		var shown = [for (e in all("screen-shown")) e.screen];
		check('stories: the new screens shown', shown.contains("Todo/One item") && shown.contains("Todo/All done") && shown.contains("Extra/Blank"), shown.join(", "));
		check('stories: a story file written on disk read', extra != null && (extra.file : String).endsWith("extra.story.tsx")
			&& (extra.screens : Array<String>).contains("Extra/Blank"), Json.stringify(extra));
		var failures = all("failure");
		var failed:Dynamic = Lambda.find(failures, e -> e.cleared != true);
		check('stories: a type error: the build\'s failure, app.tsx:88', failed != null && failed.at == "app.tsx:88" && failed.errors >= 1, Json.stringify(failures));
		var cleared:Dynamic = Lambda.find(failures, e -> e.cleared == true && ev.indexOf(e) > ev.indexOf(failed));
		check('stories: fixed: the failure cleared', failed != null && cleared != null, Json.stringify(failures));
		check('stories: no failure before the type error', failures.length > 0 && failures[0] == failed, Json.stringify(failures));
	}

	static function phone(ev:Array<Dynamic>) {
		var sheets = [for (e in ev) if (e.event == "sheet") e.sheet == null ? "none" : e.sheet + " " + e.detent];
		check('phone: the sheets opened from the bar, the handle dragged up to full and flung away, the code at half',
			sheets.join(", ") == "files half, inspect half, inspect full, none, code half", sheets.join(", "));
		var focused:Dynamic = Lambda.find(ev, e -> e.event == "focused");
		check('phone: a frame picked in the files\' sheet', focused != null && focused.screen == "app.helder#Home", Json.stringify(focused));
	}

	// the studio's own shell with the scripted agent over ACP: a turn
	// streamed, a note sent while it worked (a direction, not a prompt),
	// delivered as the next prompt once the turn was stopped; the chat put
	// away and back; a question answered in its card (reaching the agent),
	// stopped; a frame aimed at by a click; an MCP agent's question of
	// several picks, two picked in its card and sent; the canvas' hand
	// (Space held, a drag panning it)
	static function acp(ev:Array<Dynamic>) {
		var replies = ev.filter(e -> e.event == "replied");
		function reply(p:String):Dynamic
			return Lambda.find(replies, r -> StringTools.startsWith(r.prompt, p));
		var work:Dynamic = reply("work"), noted:Dynamic = reply("The user says"), wait:Dynamic = reply("wait");
		check('acp: the turn streamed, stopped', work != null && work.end == "cancelled" && (work.reply : String).indexOf("studio:screen/Home") > 0, Json.stringify(work));
		check('acp: the note a direction, then the next prompt', Lambda.exists(ev, e -> e.event == "directed" && e.text == "make the rows warmer") && noted != null
			&& ev.indexOf(noted) > ev.indexOf(work), Json.stringify(noted));
		check('acp: the chat put away and back', [for (e in ev) if (e.event == "chat") e.open].join(",") == "false,true");
		check('acp: the question answered in the card, then stopped', wait != null && wait.reply == "waiting selected" && wait.end == "cancelled", Json.stringify(wait));
		check('acp: a frame aimed at', Lambda.exists(ev, e -> e.event == "aimed" && e.screen != null));
		check('acp: the hand: open with Space, closed panning, the arrow after', [for (e in ev) if (e.event == "hand") e.cursor].join(",") == "default,grab,grabbing,grab,default",
			Json.stringify([for (e in ev) if (e.event == "hand") e.cursor]));
		var several:Dynamic = Lambda.find(ev, e -> e.event == "answered" && e.question == "Which rows should glow?");
		check('acp: an MCP agent\'s question of several picks: two picked, sent', several != null && (several.picked : Array<String>).join(",") == "done,new",
			Json.stringify(several));
	}

	static function files(original:String, final_:String, ev:Array<Dynamic>, dir:String) {
		var opened = [for (e in ev) if (e.event == "opened") e.file + " " + e.kind];
		check('files: the folders opened, the image, the font and the code each in its view',
			opened.join(", ") == "assets dir, fonts dir, src dir, assets/shapes.png image, fonts/HankenGrotesk-Medium.ttf font, src/Main.hx code", opened.join(", "));
		var inserted:Dynamic = Lambda.find(ev, e -> e.event == "image-inserted");
		check('files: the image dragged onto the Home frame', inserted != null && inserted.screen == "app.helder#Home" && inserted.src == "assets/shapes.png", Json.stringify(inserted));
		check('files: the file: an <image> of the image\'s path and size, last in the frame',
			final_ != original && final_.indexOf('<image src="assets/shapes.png" width={48} height={48}/>') > 0);
		var dropped:Dynamic = Lambda.find(ev, e -> e.event == "dropped");
		check('files: a file dropped from the system on the assets folder copied there',
			dropped != null && (dropped.files : Array<String>).join(",") == "assets/boxes.png" && FileSystem.exists('$dir/assets/boxes.png'), Json.stringify(dropped));
	}

	static function design(original:String, final_:String, ev:Array<Dynamic>) {
		function all(name:String):Array<Dynamic>
			return ev.filter(e -> e.event == name);
		var shown:Dynamic = all("designs-shown")[0];
		check('design: both frames drawn, none marked', shown != null && shown.frames == 2 && shown.errors == 0, Json.stringify(shown));
		check('design: nothing built or run', all("building").length == 0 && all("built").length == 0 && all("all-shown").length == 0);
		// (the file's text after each edit, its changes applied in order to the one before)
		var edits = all("edited"), texts = [original];
		for (e in edits) {
			var t = texts[texts.length - 1], b = new StringBuf(), at = 0;
			for (c in (e.changes : Array<Dynamic>)) {
				b.add(t.substring(at, c.start));
				b.add(c.text);
				at = c.end;
			}
			b.add(t.substr(at));
			texts.push(b.toString());
		}
		check('design: every edit\'s span applies, in order, to the file at the end', texts[texts.length - 1] == final_);
		var drags = all("dragged");
		// (the frame moved by its caption: canvas:at alone, its y snapped to the other frame's top)
		var moved:Dynamic = drags[0];
		var frameEdits = [for (k in 0...edits.length) if (edits[k].frame <= (moved?.frame ?? -1)) k];
		var afterMove = frameEdits.length == 0 ? "" : texts[frameEdits[frameEdits.length - 1] + 1];
		var at = ~/canvas:at="(-?[0-9]+) 0" background="#f8fafc" padding="56 24 24" row-gap/;
		check('design: the frame moved by its caption, snapped (canvas:at="x 0")', moved != null && moved.kind == "frame moved" && moved.snapped >= 1
			&& at.match(afterMove) && Std.parseInt(at.matched(1)) < 0 && afterMove == original.replace('canvas:at="0 0"', 'canvas:at="${at.matched(1)} 0"'),
			Json.stringify(moved));
		var x = at.matched(1);
		// (the frame selected first by the double click's first click, then its title)
		var sel:Dynamic = Lambda.find(all("selected"), e -> e.tag != "Frame");
		check('design: the title selected (its box, its element)', sel != null && sel.tag == "text" && Json.stringify(sel.rect) == "[24,56,342,35]", Json.stringify(sel));
		var k = Lambda.findIndex(edits, (e:Dynamic) -> e.origin == "inspector");
		var color:Dynamic = edits[k];
		var cat = k < 0 ? -1 : texts[k].indexOf('color="#3b82f6">todos') + 'color="'.length;
		check('design: the colour\'s edit: #3b82f6\'s span alone', color != null && color.changes.length == 1
			&& color.changes[0].start == cat && color.changes[0].end == cat + 7 && color.changes[0].text == "#ef4444", Json.stringify(color));
		check('design: undone and redone', k >= 0 && edits[k + 1]?.origin == "undo" && edits[k + 2]?.origin == "redo", Json.stringify(edits.map((e:Dynamic) -> e.origin)));
		// (each edit's frame drawn again with it: the title's colour then)
		var colors = [];
		for (e in edits.slice(k, k + 3)) {
			var next:Dynamic = Lambda.find(all("selection"), (s:Dynamic) -> s.frame > e.frame);
			colors.push(next == null || next.frame - e.frame > 3 ? null : next.color);
		}
		check('design: the title drawn #ef4444, #3b82f6, #ef4444 within 3 frames of each edit', colors.join(" ") == "#ffef4444 #ff3b82f6 #ffef4444", colors.join(" "));
		// (the title resized by its right handle, snapped to the frame's centre: width 171, one entry)
		var resized:Dynamic = drags[1];
		var colored = texts[k + 3];
		check('design: the title resized, snapped to the frame\'s centre', resized != null && resized.kind == "resized" && resized.snapped >= 1
			&& Std.string(resized.elements[0]).indexOf('color="#ef4444" width={171}>') > 0, Json.stringify(resized));
		var two = all("selected").filter((e:Dynamic) -> e.frame > (resized?.frame ?? 0));
		check('design: shift-click: two selected, then one', two.length >= 2 && two[0].others == 1 && two[1].others == 0, Json.stringify(two));
		var re:Dynamic = all("reordered")[0];
		var r = re == null ? -1 : Lambda.findIndex(edits, (e:Dynamic) -> e.frame == re.frame);
		var reordered = r < 0 ? "" : texts[r + 1];
		check('design: the title\'s layer dragged below the input row (the markup\'s order)', re != null && re.from == 0 && re.to == 1
			&& reordered.indexOf('tag="title"') > reordered.indexOf("What needs to be done?") && reordered.indexOf("What needs to be done?") > 0, Json.stringify(re));
		var undos = edits.slice(r + 1);
		check('design: undone twice: the reorder, then the resize as one entry', r >= 0 && undos.length == 2 && undos[0].origin == "undo" && undos[1].origin == "undo"
			&& texts[r + 2] == texts[r] && texts[r + 3] == colored, Json.stringify(undos.map((e:Dynamic) -> e.origin)));
		check('design: the file: the original, the frame moved and the colour', final_ == original.replace('canvas:at="0 0"', 'canvas:at="$x 0"').replace('color="#3b82f6">todos', 'color="#ef4444">todos'));
		Sys.println('studio: design: 2 frames drawn ${shown?.ms} ms after opening, nothing built');
	}

	// against tests/studio/<golden> (BLESS: rewritten): at most 1% of the pixels more than 3 levels off
	static function image(golden:String, got:String, bless:Bool) {
		if (bless) {
			if (!FileSystem.exists(here)) FileSystem.createDirectory(here);
			File.saveBytes('$here/$golden', File.getBytes(got));
			Sys.println('studio: blessed $here/$golden');
			return;
		}
		if (!FileSystem.exists('$here/$golden')) {
			check('$golden: a golden (BLESS=1 bun run test studio)', false);
			return;
		}
		var a = helder.image.PngDecoder.decode(File.getBytes(got)), b = helder.image.PngDecoder.decode(File.getBytes('$here/$golden'));
		if (a.width != b.width || a.height != b.height) {
			check('$got: the golden\'s size', false, '${a.width}x${a.height}, not ${b.width}x${b.height}');
			return;
		}
		var off = 0, max = 0, n = a.width * a.height;
		for (p in 0...n) {
			var d = 0;
			for (k in 0...3) {
				var v = a.rgba.get(4 * p + k) - b.rgba.get(4 * p + k);
				if (v < 0) v = -v;
				if (v > d) d = v;
			}
			if (d > 3) off++;
			if (d > max) max = d;
		}
		check('$got against $here/$golden', off <= 0.01 * n, '$off pixels off, at most $max');
		Sys.println('studio: $golden ' + (off == 0 && max == 0 ? "exact" : '$off pixels off, at most $max'));
	}
}
