import haxe.io.Bytes;
import helder.async.Async;
import helder.async.Fetch;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.ui.draw.DisplayList;
import helder.ui.draw.FrameArchive;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;

using StringTools;

// A share's Board on helder.run (apps/board, built for the web into
// helder.run's /_/board/): every scene of the project's frames file (the
// studio's frames.hframes, made portable by helder share) as the studio's
// canvas draws it, by flow, its loop played while the pointer is on it;
// each scenario's Play from here (the share's web build at that scenario,
// ?scenario=, in a tab of its own). On the web it reads /board.json
// ({title, frames, scenarios, play}); natively its arguments: a frames file
// and the scenarios' names (a check's, headless).
@:renderer(helder.ui.view.NodeRenderer)
class Board implements Markup {
	static final title = signal("Board");
	static final flows:helder.view.graph.Signal<Array<Flow>> = signal([]);
	static final error = signal("");
	static var archive:Null<FrameArchive> = null;
	static var play = "/?scenario=";

	static function main() {
		// (natively UiWindow.run runs the loop and does not return: what it shows comes in after)
		Async.launch(_ -> try load() catch (e:Dynamic) error('The board could not be read: $e'));
		UiWindow.run(<Surface title={title}>
			<scroll tag="board" flexGrow={1} minHeight={0} padding="28 32" rowGap={36} background="#0f0f11" color="#e4e4e7">
				<text tag="board-title" fontSize={20} fontWeight={600}>{title()}</text>
				<Show when={error() != ""}><text tag="board-error" color="#f87171">{error()}</text></Show>
				<For each={flows()} by={(f:Flow) -> f.name}>{(f:Read<Flow>) -> flow(f())}</For>
			</scroll>
		</Surface>);
	}

	@:coroutine static function load() {
		var args = Sys.args(), frames:Bytes, playable:Array<String>;
		if (hxmc.Platform.os() == 3) {
			var info:Dynamic = haxe.Json.parse(Fetch.bytes("/board.json").toString());
			title(info.title ?? "Board");
			play = info.play ?? play;
			playable = [for (s in (info.scenarios ?? [] : Array<Dynamic>)) Std.string(s)];
			frames = Fetch.bytes(info.frames);
		} else {
			if (args.length == 0) throw "board <frames.hframes> [scenario...]";
			frames = sys.io.File.getBytes(args[0]);
			playable = args.slice(1);
			title(haxe.io.Path.withoutDirectory(args[0]));
		}
		var a = FrameArchive.decode(frames);
		if (a == null) throw "not a frames file of this helder";
		archive = a;
		flows(group(a, playable));
	}

	// (the scenes by flow: "Harbour at night/Dusk sweep" in "Harbour at night", in the file's order)
	static function group(a:FrameArchive, playable:Array<String>):Array<Flow> {
		var out:Array<Flow> = [];
		for (name in a.names()) {
			var size = a.size(name), list = a.list(name);
			if (size == null || list == null) continue;
			var cut = name.lastIndexOf("/");
			var f = cut < 0 ? "Screens" : name.substr(0, cut);
			var flow = Lambda.find(out, x -> x.name == f);
			if (flow == null) out.push(flow = {name: f, scenes: []});
			flow.scenes.push({
				name: name,
				label: cut < 0 ? name : name.substr(cut + 1),
				width: size.width,
				height: size.height,
				still: list,
				looped: a.looped(name),
				playable: playable.contains(name)
			});
		}
		return out;
	}

	static function flow(f:Flow):View
		return <view tag={"flow-" + slug(f.name)} rowGap={14}>
			<text fontSize={13} fontWeight={500} color="#a1a1aa">{f.name}</text>
			<view flexDirection="row" flexWrap={true} gap={20}>
				<For each={f.scenes}>{(s:Read<Scene>) -> scene(s())}</For>
			</view>
		</view>;

	static inline var WIDTH = 280.0;

	static function scene(s:Scene):View {
		var w = WIDTH, h = WIDTH * s.height / Math.max(1, s.width);
		var frame = new BoardFrame(s.still, s.width, s.height);
		frame.style.set({width: w, height: h});
		return <view tag={"scene-" + slug(s.name)} width={w} rowGap={8}>
			<view width={w} height={h} borderRadius={6} overflow="hidden" background="#18181b" onPointerEnter={_ -> if (s.looped) {
				var l = archive?.loop(s.name);
				if (l != null) frame.play(l.fps, l.lists);
			}} onPointerLeave={_ -> frame.stop()}>{frame}</view>
			<view flexDirection="row" alignItems="center" columnGap={8}>
				<text fontSize={12} color="#d4d4d8" flexGrow={1} minWidth={0} lineClamp={1}>{s.label + (s.looped ? "  ↻" : "")}</text>
				<Show when={s.playable}>
					<button tag={"play-" + slug(s.name)} aria-label={"Play from " + s.label} padding="4 10" borderRadius={6} background="#fafafa" color="#18181b"
						cursor="pointer" fontSize={12} onPress={() -> helder.os.Links.show(play + StringTools.urlEncode(s.name), false)}>Play from here</button>
				</Show>
			</view>
		</view>;
	}

	static function slug(s:String):String
		return ~/[^A-Za-z0-9_-]+/g.replace(s, "-").toLowerCase();
}

typedef Flow = {name:String, scenes:Array<Scene>};

typedef Scene = {
	name:String,
	label:String,
	width:Float,
	height:Float,
	still:DisplayList,
	looped:Bool,
	playable:Bool
}
