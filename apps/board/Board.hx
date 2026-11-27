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
// ({title, frames, scenarios, play, live, scenes}); natively its arguments:
// a frames file and the scenarios' names (a check's, headless). A live
// share's Board follows its room (live: the socket, helder.run's /_/live):
// each scene its owner's studio drew again is fetched (scenes + its
// sha256, a frames file of its own) and swapped in; Live shown while the
// owner is there.
@:renderer(helder.ui.view.NodeRenderer)
class Board implements Markup {
	static final title = signal("Board");
	static final flows:helder.view.graph.Signal<Array<Flow>> = signal([]);
	static final error = signal("");
	static var archive:Null<FrameArchive> = null;
	static var play = "/?scenario=";
	static final live = signal(false);
	static var playable:Array<String> = [];
	static var drawn = 0;

	static function main() {
		// (natively UiWindow.run runs the loop and does not return: what it shows comes in after)
		Async.launch(_ -> try load() catch (e:Dynamic) error('The board could not be read: $e'));
		UiWindow.run(<Surface title={title}>
			<scroll tag="board" flexGrow={1} minHeight={0} padding="28 32" rowGap={36} background="#0f0f11" color="#e4e4e7">
				<view flexDirection="row" alignItems="center" columnGap={10}>
					<text tag="board-title" fontSize={20} fontWeight={600}>{title()}</text>
					<Show when={live()}>
						<view tag="board-live" flexDirection="row" alignItems="center" columnGap={6} padding="3 9" borderRadius={10} background="#14532d">
							<view width={7} height={7} borderRadius={4} background="#4ade80"/>
							<text fontSize={11} fontWeight={600} color="#bbf7d0">Live</text>
						</view>
					</Show>
				</view>
				<Show when={error() != ""}><text tag="board-error" color="#f87171">{error()}</text></Show>
				<For each={flows()} by={(f:Flow) -> f.name + "#" + f.drawn}>{(f:Read<Flow>) -> flow(f())}</For>
			</scroll>
		</Surface>);
	}

	@:coroutine static function load() {
		var args = Sys.args(), frames:Bytes, socket:Null<String> = null, scenes = "/_/scene/";
		if (hxmc.Platform.os() == 3) {
			var info:Dynamic = haxe.Json.parse(Fetch.bytes("/board.json").toString());
			title(info.title ?? "Board");
			play = info.play ?? play;
			playable = [for (s in (info.scenarios ?? [] : Array<Dynamic>)) Std.string(s)];
			frames = Fetch.bytes(info.frames);
			socket = info.live;
			scenes = info.scenes ?? scenes;
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
		if (socket != null) follow(socket, scenes);
	}

	// the room's messages, its socket opened again when it closes
	@:coroutine static function follow(socket:String, scenes:String) {
		while (true) {
			var ws = try helder.async.http.WebSocket.open(socket) catch (_:Dynamic) null;
			var m:Null<String>;
			if (ws != null) while ((m = ws.receive()) != null) {
				var j:Dynamic = try haxe.Json.parse(m) catch (_:Dynamic) null;
				if (j == null) continue;
				if (j.t == "hello" || j.t == "live") live(j.live == true);
				// (a new version: its frames file read again, the fonts the room's scenes leave out in it)
				if (j.t == "build") try reload() catch (_:Dynamic) {}
				if ((j.t == "hello" || j.t == "frames") && j.scenes != null) {
					for (k => v in (j.scenes : haxe.DynamicAccess<Null<String>>)) room.set(k, v);
					swap(j.scenes, scenes);
				}
			}
			live(false);
			Async.delay(3);
		}
	}

	// the current version's frames file, the room's scenes on it
	@:coroutine static function reload() {
		var info:Dynamic = haxe.Json.parse(Fetch.bytes("/board.json").toString());
		var a = FrameArchive.decode(Fetch.bytes(info.frames));
		if (a == null) return;
		playable = [for (s in (info.scenarios ?? [] : Array<Dynamic>)) Std.string(s)];
		archive = a;
		var all:haxe.DynamicAccess<Null<String>> = {};
		for (k => v in room) all.set(k, v);
		swap(all, info.scenes ?? "/_/scene/");
	}

	// the room's scenes so far (a new version's frames file has them under them)
	static final room = new Map<String, Null<String>>();

	// scenes drawn again: each one's own frames file fetched, in place of its still (null: gone)
	@:coroutine static function swap(changed:haxe.DynamicAccess<Null<String>>, scenes:String) {
		var a = archive;
		if (a == null) return;
		for (name => sha in changed) {
			if (sha == null) {
				a.remove(name);
				continue;
			}
			var one = try FrameArchive.decode(Fetch.bytes(scenes + sha)) catch (_:Dynamic) null;
			if (one != null) a.take(one, name, sha);
		}
		flows(group(a, playable));
	}

	// (the scenes by flow: "Harbour at night/Dusk sweep" in "Harbour at night", in the file's order)
	static function group(a:FrameArchive, playable:Array<String>):Array<Flow> {
		var out:Array<Flow> = [];
		drawn++;
		for (name in a.names()) {
			var size = a.size(name), list = a.list(name);
			if (size == null || list == null) continue;
			var cut = name.lastIndexOf("/");
			var f = cut < 0 ? "Screens" : name.substr(0, cut);
			var flow = Lambda.find(out, x -> x.name == f);
			if (flow == null) out.push(flow = {name: f, drawn: drawn, scenes: []});
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

// (drawn: the grouping it is of, a flow's cards built again when its scenes come again)
typedef Flow = {name:String, drawn:Int, scenes:Array<Scene>};

typedef Scene = {
	name:String,
	label:String,
	width:Float,
	height:Float,
	still:DisplayList,
	looped:Bool,
	playable:Bool
}
