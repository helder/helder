package studio;

import helder.gfx.Color;
import helder.image.Image;
import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import studio.Questions;
import studio.Theme.c;

// A question of an agent's in the chat (studio.ask: Questions), the boards'
// card (Ask.dc.html): the question, its options as thumbnails (the frames
// they point at, drawn small; an image; text options as buttons), "See them
// on the canvas" when they share a group (a click flies there), "Something
// else…" (the input's next message its answer). Picked here alone: the
// picked one ringed here and on the canvas. While it waits the card lifts.
@:renderer(helder.ui.view.NodeRenderer)
class Asks implements Markup {
	// (a thumbnail's box)
	static inline var THUMB_W = 100;
	static inline var THUMB_H = 96;

	public static function card(studio:Studio, q:Read<Question>):View
		return <view tag={"ask-" + q().id} rowGap={12} padding={12} borderRadius={Theme.CARD} background={c("card")} borderWidth={1}
			borderColor={q().answered ? c("hair") : c("hair2")} boxShadow={q().answered ? "none" : "0 16 30 rgba(0,0,0,0.6)"} transition="box-shadow 0.3s, transform 0.3s"
			transform={q().answered ? "none" : "translate(0px, -4px)"}>
			<view flexDirection="row" columnGap={8} alignItems="flex-start">
				<text flexGrow={1} minWidth={0} color={c("ink")} fontSize={Theme.CHAT_SIZE} fontWeight={Theme.MEDIUM}>{q().question}</text>
				<text flexShrink={0} fontSize={11} color={c("ink3")}>{q().answered ? "answered" : q().multiple ? "pick any" : "pick one"}</text>
				<Show when={!q().answered}>
					<view tag="ask-dot" width={6} height={6} borderRadius={3} marginTop={6} background={Color.parse(q().colour)}/>
				</Show>
			</view>
			<Show when={Lambda.exists(q().options, o -> o.screen != null || o.image != null)}>
				<view flexDirection="row" flexWrap={true} gap={8}>
					<For each={q().options.filter(o -> o.screen != null || o.image != null)} by={(o:Offer) -> o.id}>{(o:Read<Offer>) ->
						<button tag={"ask-option-" + o().id} aria-label={o().label} width={THUMB_W} rowGap={6} cursor="pointer"
							onPress={() -> studio.questions.pick(q().id, o().id)}>
							<view width={THUMB_W} height={THUMB_H} borderRadius={6} overflow="hidden" background={c("bubble")} alignItems="center" justifyContent="center"
								outlineWidth={q().picked.contains(o().id) ? 2 : 0} outlineOffset={2} outlineColor={Color.parse(q().colour)}>
								{thumb(studio, o())}
							</view>
							<text fontSize={11} color={q().picked.contains(o().id) ? c("ink") : c("ink2")} lineClamp={2}>{
								(q().picked.contains(o().id) ? "Picked · " : "") + o().label
							}</text>
						</button>
					}</For>
				</view>
			</Show>
			<Show when={Lambda.exists(q().options, o -> o.screen == null && o.image == null)}>
				<view flexDirection="row" flexWrap={true} gap={6}>
					<For each={q().options.filter(o -> o.screen == null && o.image == null)} by={(o:Offer) -> o.id}>{(o:Read<Offer>) ->
						<button tag={"ask-option-" + o().id} aria-label={o().label} height={28} padding="0 10" borderRadius={8}
							background={c("bubble")} color={c("ink")} justifyContent="center" cursor="pointer" outlineWidth={q().picked.contains(o().id) ? 2 : 0}
							outlineOffset={1} outlineColor={Color.parse(q().colour)} onPress={() -> studio.questions.pick(q().id, o().id)}>
							<text fontSize={12}>{o().label}</text>
						</button>
					}</For>
				</view>
			</Show>
			<Show when={q().text != null}>
				<text tag="ask-said" fontSize={12} color={c("ink2")}>{'You said: ${q().text}'}</text>
			</Show>
			<Show when={!q().answered}>
				<view flexDirection="row" alignItems="center" columnGap={8}>
					<Show when={group(studio, q()) != null}>
						<text tag="ask-see" fontSize={12} color={c("ink3")} cursor="pointer" onPress={_ -> {
							var g = group(studio, q());
							if (g != null) studio.flyToPlace(Replies.Spot.Group(g.file, g.title));
						}}>See them on the canvas</text>
					</Show>
					<view flexGrow={1}/>
					<Show when={q().multiple}>
						<button tag="ask-send" aria-label="Send" height={26} padding="0 10" borderRadius={7} justifyContent="center"
							cursor={q().picked.length > 0 ? "pointer" : "default"} data-disabled={q().picked.length > 0 ? "false" : "true"}
							background={q().picked.length > 0 ? c("ink") : c("hair2")} color={q().picked.length > 0 ? c("ground") : c("ink3")}
							onPress={() -> studio.questions.send(q().id)}>
							<text fontSize={12} fontWeight={Theme.MEDIUM}>Send</text>
						</button>
					</Show>
					<button tag="ask-else" aria-label="Something else" height={26} padding="0 10" borderRadius={7} justifyContent="center"
						cursor="pointer" background={studio.questions.replying() == q().id ? c("hair2") : c("bubble")} color={c("ink2")} onPress={() -> {
							studio.questions.replyTo(q().id);
							if (studio.talk.field != null) studio.talk.field.focus();
						}}>
						<text fontSize={12}>Something else…</text>
					</button>
				</view>
			</Show>
		</view>;

	// (an option's picture: its frame drawn small, a screen's last frame, an image)
	// (kept ones once answered: the frames may be gone)
	static function thumb(studio:Studio, o:Offer):View {
		if (o.kept != null) return design(() -> o.kept.markup, o.kept.width, o.kept.height);
		if (o.still != null) return <image src={o.still} width={THUMB_W} height={THUMB_H} objectFit="contain"/>;
		var p = studio.project;
		var info = o.screen == null || p == null ? null : p.screen(o.screen);
		if (info != null && info.source.match(Design(_)))
			return design(() -> studio.designs.copy(info.name), info.width > 0 ? info.width : 390, info.height > 0 ? info.height : 844);
		var s = info == null ? null : studio.previews?.screen(info.name);
		if (s != null) return <image src={s.image()} width={THUMB_W} height={THUMB_H} objectFit="contain"/>;
		var img = o.image == null ? null : picture(o.image);
		return img == null ? <text fontSize={11} color={c("dim")}>{o.label}</text> : <image src={img} width={THUMB_W} height={THUMB_H} objectFit="contain"/>;
	}

	// (a design frame's markup drawn small)
	static function design(markup:Void->Any, w:Float, h:Float):View {
		var k = Math.min(THUMB_W / w, THUMB_H / h);
		return <view width={w * k} height={h * k} overflow="hidden">
			<view width={w} height={h} transformOrigin="left top" transform={'scale($k)'} pointerEvents="none" background="#ffffff" color="#000000"
				fontFamily={helder.ui.Style.DEFAULT_FAMILY} fontSize={helder.ui.Style.DEFAULT_SIZE} fontWeight={helder.ui.Style.DEFAULT_WEIGHT}
				ref={(n:Node) -> n.theme = {rules: []}}>{markup()}</view>
		</view>;
	}

	static function picture(path:String):Null<Image> {
		#if (hxmc.target == "wasm32-wasi")
		return null;
		#else
		return try Image.decode(sys.io.File.getBytes(path)) catch (_:Dynamic) null;
		#end
	}

	// (the group its frames share: one design file's group, else null)
	static function group(studio:Studio, q:Question):Null<{file:String, title:String}> {
		var p = studio.project;
		if (p == null) return null;
		var gs = [for (o in q.options) if (o.screen != null) p.screen(o.screen)].filter(s -> s != null).map(s -> s.group == null ? null : s.file + "\n" + s.group);
		if (gs.length == 0 || gs.contains(null) || Lambda.exists(gs, g -> g != gs[0])) return null;
		var cut = gs[0].indexOf("\n");
		return {file: gs[0].substr(0, cut), title: gs[0].substr(cut + 1)};
	}
}
