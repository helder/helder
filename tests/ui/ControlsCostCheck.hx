import helder.math.Vec4;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;
import helder.ui.*;
import helder.ui.controls.*;
import helder.ui.controls.Standard;
import helder.ui.draw.*;
import helder.view.*;

// The controls' cost (bun run test ui-draw): a screen of 500 Buttons drawn
// in as many passes, pipelines and draws as 500 plain views of the same
// boxes and text (one pass, one pipeline, one draw: the renderer's single
// batch); at rest no frame asked for (the window sleeps: nothing drawn,
// nothing allocated) and an update allocating nothing
//   ControlsCostCheck
class ControlsCostCheck implements Markup {
	static inline var W = 1200;
	static inline var H = 900;
	static inline var N = 500;
	static var failed = 0;

	static function check(what:String, ok:Bool, detail:String) {
		Sys.println('ControlsCostCheck: ${ok ? "ok" : "FAIL"}: $what: $detail');
		if (!ok) failed++;
	}

	static function main() {
		helder.text.SystemFonts.get().add(sys.io.File.getBytes("src/helder/text/fonts/Inter.ttf"));
		var device = Device.create(Surface.headless(W, H));
		var plain = measure(device, <view flexDirection="row" flexWrap padding={8} gap={4}>
			{[for (i in 0...N) <view flexDirection="row" alignItems="center" height={28} padding="0 10" borderRadius={6} borderWidth={1}
				borderColor="#d4d4d8" background="#ffffff" fontFamily="Inter" fontSize={13}><text>{'Item $i'}</text></view>]}
		</view>);
		var buttons = measure(device, <view flexDirection="row" flexWrap padding={8} gap={4}>
			{[for (i in 0...N) <Standard.Button size="sm">{'Item $i'}</Standard.Button>]}
		</view>);
		check('$N buttons, the plain views\' passes, pipelines and draws', buttons.passes == plain.passes && buttons.pipelines == plain.pipelines
			&& buttons.draws == plain.draws, 'buttons ${buttons.passes} pass, ${buttons.pipelines} pipeline, ${buttons.draws} draw (${buttons.quads} quads); views ${plain.passes}, ${plain.pipelines}, ${plain.draws} (${plain.quads} quads)');
		check('$N buttons at rest', buttons.rests && buttons.bytes <= plain.bytes,
			'no frame asked for: ${buttons.rests}; an update ${buttons.bytes} bytes (views ${plain.bytes}); a paint, were one asked, ${buttons.paints} bytes (views ${plain.paints})');
		device.dispose();
		Sys.exit(failed == 0 ? 0 : 1);
	}

	// (a screen's frame at rest: its passes, pipelines, draws and quads, bytes allocated a frame)
	static function measure(device:Device, v:View):{passes:Int, pipelines:Int, draws:Int, quads:Int, bytes:Float, paints:Float, rests:Bool} {
		var ui = new Ui(helder.ui.TextEngines.standard(), W, H);
		var dispose = Render.render(v, ui.root);
		var r = new Renderer(device);
		for (_ in 0...4)
			frame(device, r, ui);
		FrameCounts.reset();
		frame(device, r, ui);
		var passes = FrameCounts.passes, pipelines = FrameCounts.pipelines, draws = FrameCounts.draws, quads = FrameCounts.quads;
		// (what the UI allocates a frame: its update, then its paint into the
		// renderer, begin to end, FrameCounts.uiBytes; not the device's
		// frame, which headless reads back)
		FrameCounts.reset();
		updated = 0;
		for (_ in 0...20)
			frame(device, r, ui);
		var bytes = updated / 20, paints = FrameCounts.uiBytes / 20;
		var rests = !ui.needsFrame && !Clock.active;
		dispose();
		return {passes: passes, pipelines: pipelines, draws: draws, quads: quads, bytes: bytes, paints: paints, rests: rests};
	}

	static var updated = 0.0;
	static final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}]};

	static function frame(device:Device, r:Renderer, ui:Ui) {
		var before = hxmc.GcStats.threadBytesAllocated();
		ui.update();
		updated += hxmc.GcStats.threadBytesAllocated() - before;
		var enc = device.beginFrame();
		r.begin(W, H);
		ui.paint(r);
		r.prepare(enc);
		enc.beginPass(pass);
		r.end(enc);
		enc.endPass();
		device.endFrame();
	}
}
