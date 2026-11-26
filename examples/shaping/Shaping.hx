// title: Text shaping
// summary: Fonts parsed, shaped and rasterized in Haxe: kerning, Arabic joining, right-to-left and mixed runs, combining marks; type to reshape
// tags: ui, text, bidi, shaping
// demo: canvas 480x440
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import helder.view.graph.Graph.*;

// What helder.text does for ui's text, with no system text engine: each
// line is shaped (kerning pairs, Arabic letters joined by their position in
// the word), split into runs by the bidi algorithm and laid out right to
// left where it reads so, and drawn from glyphs our own rasterizer made.
// The field below reshapes what is typed into it. In a window:
//
//   haxe -lib helder -cp examples/shaping -main Shaping --custom-target hxmc=shaping -D hxmc.libc=glibc
class Shaping implements Markup {
	static function main() {
		UiWindow.run(<Surface title="Text shaping" width={480} height={440}>{new Shaping().view()}</Surface>);
	}

	public final input = signal("Haxe كتب 2026 שלום, café");

	public function new() {}

	static function Sample(props:{label:String, text:String}):View
		return <view flexDirection="row" columnGap={12} alignItems="center">
			<text width={92} fontSize={12} color="#71717a">{props.label}</text>
			<text fontSize={20}>{props.text}</text>
		</view>;

	public function view():View
		return <view flexGrow={1} padding={20} rowGap={10} background="#fafafa" fontSize={14} color="#18181b">
			<text fontSize={22} fontWeight={700}>Text in pure Haxe</text>
			<view rowGap={8} background="#ffffff" borderRadius={8} borderWidth={1} borderColor="#e4e4e7" padding={12}>
				<Sample label="Kerning" text="AVATAR Tower WAVE"/>
				<Sample label="Arabic" text="مرحبا بالعالم"/>
				<Sample label="Hebrew" text="שלום עולם"/>
				<Sample label="Mixed" text="hxmc يكتب WebAssembly"/>
				<Sample label="Marks" text={"n\u0303 a\u0308 o\u0323\u0302 e\u0301"}/>
				<Sample label="Scripts" text="Ελληνικά Кириллица"/>
			</view>
			<field value={input} placeholder="Type in any script" aria-label="Text to shape" onInput={e -> input(e.text)} padding="8 12" borderRadius={6}
				borderWidth={1} borderColor="#e4e4e7" background="#ffffff"/>
			<text fontSize={26}>{input}</text>
		</view>;
}
