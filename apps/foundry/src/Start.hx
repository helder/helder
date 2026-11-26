import helder.gfx.Color;
import Model;
import helder.asset.Asset;
import helder.text.FontFile;
import helder.ui.*;
import helder.ui.widgets.Theme;
import helder.ui.widgets.Theme.c;
import helder.ui.view.UiFlow.Popover;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;

// Where a font starts: Pebble (Foundry's own, pen lines), an open font's
// own outlines (Outlines: Inter, Hanken Grotesk, Geist Mono, each under
// the SIL Open Font License, as what is made from it stays), a font file
// of the user's (desktop), or nothing. Each card set in its own font.
@:renderer(helder.ui.view.NodeRenderer)
class Start implements Markup {
	public static inline var PEBBLE = "Foundry Pebble";

	static final STARTERS:Array<Starter> = [
		{
			id: "pebble",
			name: "Pebble",
			about: "A round monoline sans drawn in Foundry: about fifty letters, the rest borrowed.",
			family: PEBBLE,
			license: "Foundry's own, MIT"
		},
		{
			id: "inter",
			name: "Inter",
			about: "A neutral grotesk for screens by Rasmus Andersson, its outlines as they are.",
			family: "Inter",
			license: "SIL Open Font License 1.1",
			file: () -> Asset.embed("fonts/Inter.ttf")
		},
		{
			id: "hanken",
			name: "Hanken Grotesk",
			about: "A friendly geometric grotesk by Alfredo Marco Pradil, its outlines as they are.",
			family: "Hanken Grotesk",
			license: "SIL Open Font License 1.1",
			file: () -> Asset.embed("fonts/HankenGrotesk-Regular.ttf")
		},
		{
			id: "geist",
			name: "Geist Mono",
			about: "A monospace by Vercel, every letter as wide as the next, its outlines as they are.",
			family: "Geist Mono",
			license: "SIL Open Font License 1.1",
			file: () -> Asset.embed("fonts/GeistMono-Regular.ttf")
		}
	];

	// the faces the cards are set in that are not the system's: Pebble's
	public static function fonts()
		try helder.text.SystemFonts.get().add(Draft.encode(Sample.face(), PEBBLE)) catch (_:Dynamic) {}

	public static function view(ws:Workshop):View {
		var busy = signal("");
		function pick(s:Starter) {
			if (busy.peek() != "") return;
			busy(s.id);
			// (a frame drawn first, to show which is being traced)
			var frames = 0;
			Clock.add(_ -> {
				if (++frames < 3) return true;
				var face = s.file == null ? Sample.face() : Outlines.face(FontFile.parse(s.file()), "My " + s.name);
				busy("");
				ws.begin(face);
				ws.say(s.file == null ? 'Started from ${s.name}' : 'Started from ${s.name}\'s outlines, ${countDrawn(face)} letters: ${s.license}');
				return false;
			});
		}
		function blank() {
			ws.begin(Model.empty("My Font"));
			ws.say("A blank font: trace the grey letter behind each one, or draw your own");
		}
		function open() {
			var path = helder.os.FileDialog.pick(helder.os.App.windows[0], "Open a font", [{name: "Fonts", extensions: ["ttf", "otf"]}]);
			if (path == null) return;
			try {
				var face = Outlines.face(FontFile.parse(sys.io.File.getBytes(path)), "My Font");
				ws.begin(face);
				ws.say('Started from ${haxe.io.Path.withoutDirectory(path)}: keep to its license when you share what you make');
			} catch (e:Dynamic) {
				ws.say('Could not read that font ($e)');
			}
		}
		return <Popover open={ws.starting} modal placement="center" scrim={Color.rgba(0, 0.5)} onDismiss={() -> ws.starting(false)}>
			<view tag="start" role="dialog" aria-label="Start a font" width={860} padding={28} rowGap={20} borderRadius={Theme.RADIUS_M + 4} background={c("bg")}
				borderWidth={1} borderColor={c("edge")} boxShadow={Theme.popover()}>
				<view rowGap={6}>
					<text fontSize={22} fontWeight={Theme.MEDIUM}>Start a font</text>
					<text color={c("fg2")}>Pick where to begin. Every letter stays yours to redraw: the pen, the proportions and the spacing too.</text>
				</view>
				<view display="grid" gridTemplateColumns="repeat(4, 1fr)" columnGap={12}>
					<For each={STARTERS}>{(s:Read<Starter>) -> card(s(), busy, pick)}</For>
				</view>
				<view flexDirection="row" alignItems="center" columnGap={8}>
					<button tag="start-blank" slot="button" aria-label="Start blank" onPress={blank}>
						<image src={Icons.pen} width={14} height={14}/><text>Start blank</text>
					</button>
					<Show when={helder.os.FileDialog.available()}>
						<button tag="start-file" slot="button" aria-label="Open a font file" onPress={open}>
							<image src={Icons.download} width={14} height={14}/><text>Open a font file…</text>
						</button>
					</Show>
					<view flexGrow={1}/>
					<text fontSize={Theme.SMALL} color={c("fg3")}>A font made from an OFL font is shared under the OFL too.</text>
				</view>
			</view>
		</Popover>;
	}

	static function card(s:Starter, busy:Read<String>, pick:Starter->Void):View
		return <button tag={"start-" + s.id} slot="starter" aria-label={"Start from " + s.name} onPress={() -> pick(s)}>
			<view height={120} alignItems="center" justifyContent="center" borderRadius={Theme.RADIUS_M} background={c("well")}>
				<Show when={busy() == s.id} fallback={<text fontFamily={s.family} fontSize={58} lineHeight="64px" color={c("fg")}>Ag</text>}>
					<text color={c("fg2")}>Reading…</text>
				</Show>
			</view>
			<view rowGap={4} padding="10 2 0">
				<text fontWeight={Theme.MEDIUM}>{s.name}</text>
				<text fontSize={Theme.SMALL} color={c("fg2")} lineHeight="16px">{s.about}</text>
				<text fontSize={10} color={c("fg3")} padding="4 0 0">{s.license}</text>
			</view>
		</button>;

	static function countDrawn(f:Face):Int
		return [for (k in f.glyphs.keys()) k].length;
}

private typedef Starter = {id:String, name:String, about:String, family:String, license:String, ?file:Void->haxe.io.Bytes};
