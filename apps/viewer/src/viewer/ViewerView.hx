package viewer;

import helder.ui.Clock;
import helder.ui.widgets.WindowButtons;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// A file full size: its bar (the back pill "‹ folder", the title, Move
// to Trash), then the image view on the dark background, the player of a
// video or an audio file, a message in place of the image (loading, an
// error), the status line (I) and the go to page card. Fullscreen: the
// bar hidden.
class ViewerView implements Markup {
	public static inline var BAR = 52;
	public static inline var BACKGROUND = "#161618";

	public static function make(x:Explorer):View {
		var viewer = x.viewer;
		var image = new ImageView(viewer);
		image.onContextMenu = (px, py) -> if (image.ui != null) helder.ui.menu.Menus.popup(image.ui, ViewerActions.context, px, py, image);
		image.focusable = true;
		image.style.position = Absolute;
		image.style.left = image.style.top = image.style.right = image.style.bottom = 0;
		// (to assistive technology an image, named as the window is: the file, its place, its size)
		image.semantics = {role: helder.ui.access.Role.Image, label: viewer.title.peek()};
		renderEffect(() -> viewer.title(), t -> image.semantics.label = t);
		// (opened: the keys the image's)
		renderEffect(() -> x.full(), on -> if (on) Clock.add(_ -> {
			if (image.ui != null) image.focus(false);
			false;
		}));
		// (a change drawn; an animation or a glide ticked on the clock while it lasts)
		var ticking = false, last = -1.0;
		renderEffect(() -> viewer.version(), _ -> {
			image.redraw();
			if (ticking) return;
			ticking = true;
			last = -1;
			Clock.add(t -> {
				var dt = last < 0 ? 0 : Math.min(0.1, t - last);
				last = t;
				var more = viewer.tick(t, dt);
				image.redraw();
				if (!more) ticking = false;
				return more;
			});
		});
		// (Loading… only once a decode takes a moment: no flash on the first frame, nor on a flip to one about to land)
		var slow = signal(false), waitFrom = -1.0;
		renderEffect(() -> viewer.state() == Loading, loading -> {
			slow(false);
			if (!loading || waitFrom >= 0) return;
			waitFrom = 0;
			Clock.add(t -> {
				if (waitFrom == 0) waitFrom = t;
				if (viewer.state.peek() != Loading) {
					waitFrom = -1;
					return false;
				}
				if (t - waitFrom < 0.25) return true;
				waitFrom = -1;
				slow(true);
				return false;
			});
		});
		return <view tag="viewer" position="absolute" inset={0} background={BACKGROUND} color="#e4e4e7" font-size={13} display={x.full() ? "flex" : "none"}>
			<view tag="viewer-bar" direction="row" align-items="center" column-gap={8} height={BAR} shrink={0} drag-region
				padding-left={WindowButtons.side() == "start" ? 86 : 14} padding-right={WindowButtons.side() == "end" ? 152 : 14}
				display={viewer.fullscreen() ? "none" : "flex"}>
				<view:button tag="back-pill" role="button" focusable label={() -> "Back to " + x.sidebar.title(x.browser.dir())} direction="row"
					align-items="center" column-gap={6} height={30} padding="0 12 0 6" radius={8} background="rgba(255,255,255,0.09)" color="#f1f1f1"
					font-weight={500} shrink={1} min-width={0} onPress={() -> x.close()}>
					<image src={Glyphs.get("back")} width={16} height={16} shrink={0}/>
					<image src={() -> Glyphs.get(x.browser.layout() == Grid ? "grid" : "list")} width={14} height={14} shrink={0}/>
					<text max-lines={1} text-overflow="ellipsis">{() -> x.sidebar.title(x.browser.dir())}</text>
				</view:button>
				<text tag="viewer-title" grow={1} shrink={1} min-width={0} text-align="center" max-lines={1} text-overflow="ellipsis" color="#a1a1aa"
					dir={helder.ui.Dir.Ltr}>{viewer.title}</text>
				<Show when={x.files.trash != null}>
					<view:button tag="viewer-trash" role="button" focusable label={ViewerActions.trashLabel()} width={30} height={30} radius={8}
						align-items="center" justify="center" color="#d6d6d6" onPress={() -> x.perform(Trash)}>
						<image src={Glyphs.get("trash")} width={16} height={16}/>
					</view:button>
				</Show>
			</view>
			<view tag="stage" grow={1} min-height={0}>
				{image}
				<Show when={viewer.media() != ""}>{MediaView.make(viewer)}</Show>
				<Show when={viewer.state() != Shown && (viewer.state() != Loading || slow())}>
					<view tag="message" position="absolute" inset={0} align-items="center" justify="center" row-gap={8} padding={24} pointer-events="none">
						<text tag="title" font-size={17} color={viewer.state() == Failed ? "#fca5a5" : "#e4e4e7"} text-align="center">{viewer.message}</text>
						<text tag="detail" color="#a1a1aa" text-align="center">{viewer.detail}</text>
					</view>
				</Show>
				<Show when={viewer.statusOn() && viewer.status() != ""}>
					<view tag="status" position="absolute" left={0} right={0} bottom={0} padding="6 12" background="#000000b3" direction="row">
						<text color="#d4d4d8">{viewer.status}</text>
					</view>
				</Show>
				<Show when={viewer.gotoOpen()}>{goTo(viewer)}</Show>
			</view>
		</view>;
	}

	static function goTo(viewer:Viewer):View
		return <view tag="goto-backdrop" position="absolute" inset={0} background="#00000066" align-items="center" justify="center"
			onClick={_ -> viewer.gotoOpen(false)}>
			<view tag="goto" width={260} padding={12} row-gap={8} radius={10} background="#232326" border-width={1} border-color="#3f3f46"
				shadow="0 8px 30px rgba(0, 0, 0, 0.5)" onClick={e -> e.stop()}>
				<text color="#a1a1aa">{"Go to page (1–" + viewer.pagesSignal() + ")"}</text>
				<field tag="goto-field" value={viewer.gotoText} placeholder={Std.string(viewer.pageSignal() + 1)} label="Page number" height={28} padding="0 8"
					radius={6} background="#18181b" border-width={1} border-color="#52525b" onInput={e -> viewer.gotoText(e.text)}
					onKeyDown={e -> if (e.key == helder.ui.Key.ENTER) {
						viewer.goToTyped((cast e.current : helder.ui.widgets.TextField).text);
						e.stop();
					}}
					ref={n -> Clock.add(_ -> {
						n.focus();
						false;
					})}/>
			</view>
		</view>;
}
