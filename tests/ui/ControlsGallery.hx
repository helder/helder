import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;
import helder.ui.*;
import helder.ui.controls.*;
import helder.ui.controls.Standard;
import helder.ui.controls.Props.PathSegment;
import helder.ui.controls.Icons;
import helder.ui.draw.*;
import helder.view.*;

// helder.ui.controls' gallery: Button (each variant, the sizes, an icon
// alone), Checkbox (off, on, mixed) and Switch (off, on), each in every
// state (rest, hover, pressed, the keyboard's focus, disabled), in
// Look.base light and dark, comfortable and compact (bun run test ui-draw):
// the states forced on their nodes, the transitions finished, the nodes'
// slots, states and styles checked, then each frame against its golden image
// (tests/ui/controls/; Linux: llvmpipe, the repository's Inter):
//   ControlsGallery <golden dir> <out dir> [--bless]
class ControlsGallery implements Markup {
	static inline var W = 760;
	static inline var H = 700;
	static final STATES = ["rest", "hover", "pressed", "focus", "disabled"];
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('ControlsGallery: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var args = Sys.args();
		for (f in ["src/helder/text/fonts/Inter.ttf", "examples/showreel/fonts/InterDisplay.ttf", "apps/studio/fonts/GeistMono-Regular.ttf"])
			helder.text.SystemFonts.get().add(sys.io.File.getBytes(f));
		var device = new DrawFrame(W, H);
		var ok = true;
		for (density in [Tokens.Density.Comfortable, Tokens.Density.Compact])
			for (dark in [false, true]) {
				var name = 'gallery-${density}-${dark ? "dark" : "light"}';
				var look:Look<Dynamic> = density == Compact ? Look.base.with({density: Compact}) : Look.base;
				var pixels = frame(device, look, dark, density);
				sys.io.File.saveBytes('${args[1]}/$name.png', helder.image.PngEncoder.encode(pixels, W, H, true));
				if (args[2] == "--bless") {
					sys.io.File.saveBytes('${args[0]}/$name.png', helder.image.PngEncoder.encode(pixels, W, H, true));
					Sys.println('ControlsGallery: blessed ${args[0]}/$name.png');
					continue;
				}
				ok = compare(name, pixels, '${args[0]}/$name.png') && ok;
			}
		device.dispose();
		Sys.println('ControlsGallery: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 && ok ? 0 : 1);
	}

	// (a gallery's frame: mounted, drawn once, its states forced, its transitions finished, checked, drawn)
	static function frame(device:DrawFrame, look:Look<Dynamic>, dark:Bool, density:Tokens.Density):Bytes {
		var ui = new Ui(new DrawText(), W, H);
		ui.dark = dark;
		var dispose = Render.render(gallery(look), ui.root);
		ui.update();
		paint(device, ui);
		ui.focusVisible = true;
		var t = look.tokens;
		for (row in ROWS)
			for (s in STATES) {
				var n = ui.root.find('${row.tag}-$s');
				if (n == null) throw 'ControlsGallery: no ${row.tag}-$s';
				switch s {
					case "hover": @:privateAccess n.setState(true, false, false);
					case "pressed": @:privateAccess n.setState(true, true, false);
					case "focus": @:privateAccess n.setState(false, false, true);
					case _:
				}
			}
		ui.update();
		Clock.finish();
		ui.update();
		Clock.finish();
		ui.update();
		var colors = dark ? look.sheet().dark : look.sheet().light;
		var at = '$density ${dark ? "dark" : "light"}';
		// (the nodes: their slots and states, the styles their states give)
		var primary = ui.root.find("primary-rest"), hovered = ui.root.find("primary-hover");
		check('$at: a primary button', primary.slot == "button" && primary.variant == "primary" && primary.size == "md", '${primary.slot} ${primary.variant}');
		check('$at: its background', primary.style.background == colors.get("accent"));
		check('$at: hovered, the accent\'s shade', hovered.style.background == colors.get("accentStrong"));
		var pressed = ui.root.find("secondary-pressed");
		check('$at: pressed, it gives', pressed.style.transform != null && Math.abs(@:privateAccess pressed.style.transform.args[0][0] - t.pressScale) < 1e-6,
			Std.string(pressed.style.transform));
		check('$at: the ring the keyboard\'s focus', ui.root.find("ghost-focus").style.ringWidth == 2 && ui.root.find("ghost-rest").style.ringWidth == 0);
		var off = ui.root.find("danger-disabled");
		check('$at: disabled', off.style.opacity == t.disabledOpacity && off.attr("data-disabled") != null && !off.focusable);
		check('$at: a size', Type.enumEq(ui.root.find("size-sm").style.height, (t.controlSm : Dim))
			&& Type.enumEq(ui.root.find("size-lg").style.height, (t.controlLg : Dim)));
		var icon = ui.root.find("size-icon");
		check('$at: an icon alone, square', icon.width == icon.height, '${icon.width} x ${icon.height}');
		var inspector = ui.root.find("inspector");
		check('$at: a selected ghost', inspector.attr("data-selected") == "" && inspector.style.background == colors.get("accentSoft"));
		check('$at: a collapsed path', ui.root.find("path-narrow").find("pathbar-overflow").style.display == Flex);
		var on = ui.root.find("checked-rest"), mixed = ui.root.find("mixed-rest");
		check('$at: a checkbox on', on.semantics.role == CheckBox && on.semantics.checked == true && on.attr("data-state") == "checked");
		check('$at: its box', on.children[0].slot == "checkbox-box" && on.children[0].style.background == colors.get("accent"));
		check('$at: mixed', mixed.semantics.mixed && mixed.attr("data-state") == "mixed");
		var sw = ui.root.find("on-rest"), knob = sw.children[0].children[0];
		var travel = t.track - t.thumb - (t.trackHeight - t.thumb);
		check('$at: a switch on, its knob across', knob.slot == "switch-knob" && knob.style.transform != null
			&& Math.abs(@:privateAccess knob.style.transform.args[0][0] - travel) < 1e-6, Std.string(knob.style.transform));
		check('$at: its track the accent', sw.children[0].style.background == colors.get("accent"));
		var pixels = paint(device, ui);
		dispose();
		return pixels;
	}

	static function paint(f:DrawFrame, ui:Ui):Bytes {
		ui.update();
		return f.draw(ui);
	}

	static function compare(name:String, pixels:Bytes, golden:String):Bool {
		if (!sys.FileSystem.exists(golden)) {
			Sys.println('ControlsGallery: FAIL: no $golden (BLESS=1 writes it)');
			return false;
		}
		var g = Png.decode(sys.io.File.getBytes(golden));
		var d = ImageDiff.of(pixels, g.rgba, W, H, 3);
		var ok = g.width == W && g.height == H && d.far <= 0.003 * W * H;
		Sys.println('ControlsGallery: $name ' + (ok ? "ok" : "FAIL") + (d.differ == 0 ? " (exact)" : ' (${d.far} pixels off, at most ${d.max})'));
		return ok;
	}

	// (the rows: a control in each state, tagged row-state)
	static final ROWS:Array<{tag:String, label:String}> = [
		{tag: "primary", label: "primary"},
		{tag: "secondary", label: "secondary"},
		{tag: "outline", label: "outline"},
		{tag: "ghost", label: "ghost"},
		{tag: "danger", label: "danger"},
		{tag: "unchecked", label: "checkbox"},
		{tag: "checked", label: "checked"},
		{tag: "mixed", label: "mixed"},
		{tag: "off", label: "switch"},
		{tag: "on", label: "on"}
	];

	static function control(tag:String, state:String):View {
		var id = '$tag-$state', off = state == "disabled";
		return switch tag {
			case "primary": <Standard.Button tag={id} variant="primary" disabled={off}>Save</Standard.Button>;
			case "secondary": <Standard.Button tag={id} variant="secondary" disabled={off}>Cancel</Standard.Button>;
			case "outline": <Standard.Button tag={id} variant="outline" disabled={off}>Share</Standard.Button>;
			case "ghost": <Standard.Button tag={id} variant="ghost" disabled={off}>More</Standard.Button>;
			case "danger": <Standard.Button tag={id} variant="danger" disabled={off}>Delete</Standard.Button>;
			case "unchecked": <Standard.Checkbox tag={id} label="Remember" disabled={off}/>;
			case "checked": <Standard.Checkbox tag={id} label="Remember" checked={true} disabled={off}/>;
			case "mixed": <Standard.Checkbox tag={id} label="All" checked={false} indeterminate={true} disabled={off}/>;
			case "off": <Standard.Switch tag={id} label="Wi-Fi" disabled={off}/>;
			case _: <Standard.Switch tag={id} label="Wi-Fi" checked={true} disabled={off}/>;
		}
	}

	static function location():Array<PathSegment>
		return [{label: "Home", icon: Icons.svg("folder")}, {label: "Pictures"}, {label: "2026"}, {label: "Reference images"}];

	static function gallery(look:Look<Dynamic>):View
		return <Standard.Themed look={look}>
			<view flexGrow={1} padding={16} rowGap={4} background={Look.ref.canvas} color={Look.ref.fg} fontFamily="Inter" fontSize={13}>
				<view flexDirection="row" height={24} alignItems="center">
					<view width={100}/>
					{[for (s in STATES) <text width={128} color={Look.ref.fg3}>{s}</text>]}
				</view>
				{[for (row in ROWS) <view flexDirection="row" alignItems="center" minHeight={48}>
					<text width={100} color={Look.ref.fg3}>{row.label}</text>
					{[for (s in STATES) <view width={128} flexDirection="row">{control(row.tag, s)}</view>]}
				</view>]}
				<view flexDirection="row" alignItems="center" minHeight={56} columnGap={12}>
					<text width={88} color={Look.ref.fg3}>sizes</text>
					<Standard.Button tag="size-sm" variant="primary" size="sm">Small</Standard.Button>
					<Standard.Button tag="size-md" variant="primary">Medium</Standard.Button>
					<Standard.Button tag="size-lg" variant="primary" size="lg">Large</Standard.Button>
					<Standard.Button tag="size-icon" icon={Icons.svg("search")} label="Search"/>
					<Standard.Button tag="inspector" icon={Icons.svg("panel-left")} variant="ghost" label="Inspector" selected={true}/>
				</view>
				<view flexDirection="row" alignItems="center">
					<text width={100} color={Look.ref.fg3}>path bar</text>
					<view width={330}>
						<Standard.PathBar segments={location()} onNavigate={_ -> {}} onSubmit={_ -> {}}/>
					</view>
					<view width={196}>
						<Standard.PathBar tag="path-narrow" segments={location()} onNavigate={_ -> {}} onSubmit={_ -> {}}/>
					</view>
				</view>
			</view>
		</Standard.Themed>;
}
