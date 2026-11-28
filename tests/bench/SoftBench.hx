import helder.ui.*;
import helder.ui.draw.*;
import helder.ui.controls.*;
import helder.view.*;

// The CPU's canvas (helder.ui.draw.soft) timed against the GPU on the same
// scenes (DrawFrame: HELDER_SOFT=1 for the CPU's): a frame painted and
// read back, the scene laid out once before, the least of RUNS frames
// (the first one, glyphs rasterized and images taken, printed apart):
//   SoftBench [rows (5000)]
// the sample UI, the todo example, the controls' gallery at 1x and 2x,
// StressCheck's list of rows, scrolled half way.
class SoftBench {
	static inline var RUNS = 20;

	static function main() {
		var rows = Sys.args().length > 0 ? Std.parseInt(Sys.args()[0]) : 5000;
		for (f in ["src/helder/text/fonts/Inter.ttf"])
			helder.text.SystemFonts.get().add(sys.io.File.getBytes(f));
		var out = [];
		function scene(name:String, w:Int, h:Int, scale:Float, build:Ui->Void) {
			var ui = new Ui(helder.ui.TextEngines.standard(), w, h);
			ui.scale = scale;
			build(ui);
			ui.update();
			Clock.finish();
			ui.update();
			var f = new DrawFrame(Math.round(w * scale), Math.round(h * scale));
			f.scale = scale;
			f.groups = true;
			var t0 = haxe.Timer.stamp();
			var px = f.draw(ui);
			var first = haxe.Timer.stamp() - t0, best = 1e9;
			for (i in 0...RUNS) {
				var t = haxe.Timer.stamp();
				f.draw(ui, px);
				best = Math.min(best, haxe.Timer.stamp() - t);
			}
			out.push('$name ${Math.round(w * scale)}x${Math.round(h * scale)}: ${ms(best)} ms (first ${ms(first)})');
			Sys.println('SoftBench ($f): ${out[out.length - 1]}');
			f.dispose();
		}
		scene("sample", 480, 320, 1, ui -> Sample.build(ui.root));
		scene("todo", 480, 560, 1, ui -> {
			var app = new Todo();
			Render.render(app.view(), ui.root);
		});
		for (k in [1.0, 2.0])
			scene('gallery@${k}x', 760, 660, k, ui -> @:privateAccess Render.render(ControlsGallery.gallery(Look.base), ui.root));
		scene('stress $rows', 800, 600, 1, ui -> {
			var app = @:privateAccess new StressCheck(rows);
			Render.render(@:privateAccess app.view(), ui.root);
			ui.update();
			var list = ui.root.find("list");
			ui.wheel(400, 300, 0, list.contentHeight / 2);
		});
	}

	static function ms(s:Float):Float
		return Math.round(s * 10000) / 10;
}
