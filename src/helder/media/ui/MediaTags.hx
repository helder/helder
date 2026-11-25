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
		?src:helder.view.graph.Read<haxe.extern.EitherType<String, helder.media.ByteSource>>,
		?fit:ImageFit,
		?autoplay:Bool,
		?loop:Bool,
		?muted:helder.view.graph.Read<Bool>,
		?volume:helder.view.graph.Read<Float>,
		?rate:helder.view.graph.Read<Float>,
		?layer:Bool,
		?grow:Float,
		?width:helder.view.graph.Read<helder.ui.Dim>,
		?height:helder.view.graph.Read<helder.ui.Dim>,
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
		if (props.fit != null) v.fit = props.fit;
		v.onLoaded = props.onLoaded;
		v.onEnded = props.onEnded;
		v.onError = props.onError;
		v.onTime = props.onTime;
		if (props.muted != null) Graph.renderEffect(() -> props.muted(), m -> v.muted = m);
		if (props.volume != null) Graph.renderEffect(() -> props.volume(), k -> v.volume = k);
		if (props.rate != null) Graph.renderEffect(() -> props.rate(), k -> v.rate = k);
		if (props.src != null) Graph.renderEffect(() -> props.src(), s -> v.open(s));
		if (props.grow != null) NodeRenderer.setProperty(v, "grow", props.grow);
		if (props.width != null) Graph.renderEffect(() -> props.width(), x -> NodeRenderer.setProperty(v, "width", x));
		if (props.height != null) Graph.renderEffect(() -> props.height(), x -> NodeRenderer.setProperty(v, "height", x));
		Graph.onCleanup(v.dispose);
		if (props.ref != null) props.ref(v);
		return v;
	}
}
