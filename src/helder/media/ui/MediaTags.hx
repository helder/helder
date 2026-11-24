package helder.media.ui;

import helder.ui.ImageFit;
import helder.ui.view.NodeRenderer;
import helder.view.Render;
import helder.view.graph.Graph;

// helder.media's markup, imported with import helder.media.ui.MediaTags.*:
//
//   <Video src="clip.mp4" fit="cover" autoplay loop muted grow={1} ref={v -> video = v}/>
//
// layer={true}: the system's AVSampleBufferDisplayLayer where the window
// has system layers, not helder's drawing (VideoNode.layer)
//
// <Video> is a box of helder.ui's showing a video (VideoNode): src a path
// or a helder.media.ByteSource (a file's bytes: a MemorySource; a signal:
// another file when it changes); its player's controls are the node's
// (ref): play, pause, seek, step, and its time, duration and playing
// signals. An audio file plays the same way without a box (helder.media.Player).
class MediaTags {
	public static function Video(props:{
		?src:Dynamic,
		?fit:Dynamic,
		?autoplay:Bool,
		?loop:Bool,
		?muted:helder.view.graph.Read<Bool>,
		?volume:helder.view.graph.Read<Float>,
		?rate:helder.view.graph.Read<Float>,
		?layer:Bool,
		?grow:Float,
		?width:helder.view.graph.Read<Dynamic>,
		?height:helder.view.graph.Read<Dynamic>,
		?style:Dynamic,
		?onLoaded:Void->Void,
		?onEnded:Void->Void,
		?onError:String->Void,
		?onTime:Float->Void,
		?ref:VideoNode->Void
	}):helder.ui.Node {
		var v = new VideoNode();
		if (props.autoplay != null) v.autoplay = props.autoplay;
		if (props.loop != null) v.loop = props.loop;
		if (props.layer != null) v.layer = props.layer;
		if (props.fit != null) v.fit = fit(props.fit);
		v.onLoaded = props.onLoaded;
		v.onEnded = props.onEnded;
		v.onError = props.onError;
		v.onTime = props.onTime;
		bind(props.muted, (m:Bool) -> v.muted = m);
		bind(props.volume, (k:Float) -> v.volume = k);
		bind(props.rate, (k:Float) -> v.rate = k);
		bind(props.src, s -> v.open(s));
		if (props.grow != null) NodeRenderer.setProperty(v, "grow", props.grow);
		if (props.width != null) bind(props.width, x -> NodeRenderer.setProperty(v, "width", x));
		if (props.height != null) bind(props.height, x -> NodeRenderer.setProperty(v, "height", x));
		if (props.style != null) NodeRenderer.setStyle(v, props.style);
		Graph.onCleanup(v.dispose);
		if (props.ref != null) props.ref(v);
		return v;
	}

	static function bind<T>(value:Null<Dynamic>, set:T->Void)
		if (value != null) Render.isReactive(value) ? Graph.renderEffect(() -> (Render.read(value) : T), set) : set(Render.read(value));

	static function fit(v:Dynamic):ImageFit
		return Std.isOfType(v, String) ? switch (v : String).toLowerCase() {
			case "fill": Fill;
			case "cover": Cover;
			case "none": ImageFit.None;
			case _: Contain;
		} : v;
}
