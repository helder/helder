package viewer;

import helder.ui.Clock;
import helder.ui.controls.Look;
import helder.ui.UiWindow;
import helder.ui.widgets.WindowButtons;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// A file full size: its bar (the back pill "‹ folder", the title, a
// Markdown document's Source, Move to Trash), then the image view on the
// dark background, the player of a video or an audio file, a Markdown
// document's column, a message in place of the image (loading, an
// error), the status line (I) and the go to page card. Fullscreen: the
// bar hidden.
@:renderer(helder.ui.view.NodeRenderer)
class ViewerView implements Markup {
	public static inline var BAR = 52;

	// the look's canvas as 0xRRGGBB, dark or light (the image's backdrop, the window's)
	public static function canvas(dark:Bool):Int {
		var t = Shell.look.tokens.canvas;
		return (dark ? t.dark : t.light : Int) & 0xFFFFFF;
	}

	public static function make(x:Explorer):View {
		var viewer = x.viewer;
		return <view tag="viewer" position="absolute" inset={0} background={Look.ref.canvas} color={Look.ref.fg} fontSize={13}
			opacity={x.zoom.shown()} pointerEvents={x.full() ? "auto" : "none"} aria-hidden={!x.full()}>
			<view tag="viewer-bar" flexDirection="row" alignItems="center" columnGap={8} height={BAR} flexShrink={0} dragRegion
				paddingLeft={WindowButtons.side() == "start" ? Shell.BUTTONS : 14} paddingRight={WindowButtons.side() == "end" ? 152 : 14}
				display={viewer.fullscreen() ? "none" : "flex"}>
				<button tag="back-pill" aria-label={() -> "Back to " + x.sidebar.title(x.browser.dir())} flexDirection="row"
					alignItems="center" columnGap={6} height={30} padding="0 12 0 6" borderRadius={8} background={Look.ref.fill} color={Look.ref.fg}
					fontWeight={500} flexShrink={1} minWidth={0} onPress={() -> x.close()}>
					<image src={Glyphs.get("back")} width={16} height={16} flexShrink={0}/>
					<image src={() -> Glyphs.get(x.browser.layout() == Grid ? "grid" : "list")} width={14} height={14} flexShrink={0}/>
					<text lineClamp={1} textOverflow="ellipsis">{() -> x.sidebar.title(x.browser.dir())}</text>
				</button>
				<text tag="viewer-title" flexGrow={1} flexShrink={1} minWidth={0} textAlign="center" lineClamp={1} textOverflow="ellipsis" color={Look.ref.fg2}
					direction={helder.ui.Dir.Ltr}>{viewer.title}</text>
				<Show when={viewer.markdown() != null}>
					<button tag="viewer-source" aria-label="Show Source" data-selected={viewer.markdown()?.source() == true}
						flexDirection="row" alignItems="center" columnGap={5} height={30} padding="0 10 0 8" borderRadius={8}
						background={viewer.markdown()?.source() == true ? Look.ref.fill : null} color={Look.ref.fg2}
						onPress={() -> x.perform(ToggleSource)}>
						<image src={Glyphs.get("code")} width={16} height={16}/>
						<text>Source</text>
					</button>
				</Show>
				<Show when={x.files.trash != null}>
					<button tag="viewer-trash" aria-label={ViewerActions.trashLabel()} width={30} height={30} borderRadius={8}
						alignItems="center" justifyContent="center" color={Look.ref.fg2} onPress={() -> x.perform(Trash)}>
						<image src={Glyphs.get("trash")} width={16} height={16}/>
					</button>
				</Show>
			</view>
			{stage(x)}
		</view>;
	}

	// the file itself: the image (its view's own presses: a drag pans, a
	// double click zooms), a video's or an audio file's player, a PDF's
	// column, the message in their place, the status line, go to page; the
	// browser's and a phone's
	public static function stage(x:Explorer):View {
		var viewer = x.viewer;
		var image = new ImageView(viewer);
		image.onContextMenu = (px, py) -> if (image.ui != null) helder.ui.menu.Menus.popup(image.ui, ViewerActions.context, px, py, image);
		image.focusable = true;
		x.zoom.view(image);
		// (a pinch in at the fit, a swipe down: closed following the fingers, Flight; else the viewer's)
		var wheel = image.onWheel;
		image.onWheel = e -> if (x.zoom.fullWheel(e)) e.preventDefault() else if (wheel != null) wheel(e);
		// (its picture in flight: the image under it not drawn)
		renderEffect(() -> x.zoom.flying() != "", on -> image.veiled = on);
		renderEffect(() -> UiWindow.dark(), d -> image.background = canvas(d));
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
		// (the file over the status line, not under it: the media bar, the PDF's column, the picture all above it)
		return <view tag="stage" flexGrow={1} minHeight={0}>
			<view tag="stage-content" flexGrow={1} minHeight={0}>
				{image}
				<Show when={viewer.media() != ""}>{MediaView.make(viewer, x.files)}</Show>
				<Show when={viewer.pdf() != null}>{() -> {
					var d = viewer.pdf();
					d == null ? null : PdfView.make(d);
				}}</Show>
				<Show when={viewer.markdown() != null}>{() -> {
					var d = viewer.markdown();
					d == null ? null : MarkdownPage.make(x, d);
				}}</Show>
				<Show when={viewer.state() != Shown && (viewer.state() != Loading || slow()) && x.zoom.flying() == ""}>
					<view tag="message" position="absolute" inset={0} alignItems="center" justifyContent="center" rowGap={8} padding={24} pointerEvents="none">
						<text tag="title" fontSize={17} color={viewer.state() == Failed ? Look.ref.danger : Look.ref.fg} textAlign="center">{viewer.message}</text>
						<text tag="detail" color={Look.ref.fg3} textAlign="center">{viewer.detail}</text>
					</view>
				</Show>
				<Show when={viewer.gotoOpen()}>{goTo(viewer)}</Show>
			</view>
			<Show when={viewer.statusOn() && viewer.status() != ""}>
				<view tag="status" flexShrink={0} padding="6 12" background={Look.ref.raised} borders="1 0 0 0" borderColor={Look.ref.line} flexDirection="row">
					<text flexShrink={1} minWidth={0} lineClamp={1} textOverflow="ellipsis" color={Look.ref.fg2}>{viewer.status}</text>
				</view>
			</Show>
		</view>;
	}

	static function goTo(viewer:Viewer):View
		return <view tag="goto-backdrop" position="absolute" inset={0} background={Look.ref.scrim} alignItems="center" justifyContent="center"
			onPress={_ -> viewer.gotoOpen(false)}>
			<view tag="goto" width={260} padding={12} rowGap={8} borderRadius={10} background={Look.ref.raised} borderWidth={1} borderColor={Look.ref.edge}
				boxShadow="0 8px 30px rgba(0, 0, 0, 0.25)" onPress={e -> e.stop()}>
				<text color={Look.ref.fg3}>{"Go to page (1–" + viewer.pagesSignal() + ")"}</text>
				<field tag="goto-field" value={viewer.gotoText} placeholder={Std.string(viewer.pageSignal() + 1)} aria-label="Page number" height={28} padding="0 8"
					borderRadius={6} background={Look.ref.well} borderWidth={1} borderColor={Look.ref.edge} onInput={e -> viewer.gotoText(e.text)}
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
