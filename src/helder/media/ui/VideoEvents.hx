package helder.media.ui;

// <video>'s own events, by attribute (helder.view.Vocabulary's, beside
// helder.ui's NodeEvents): its file read (the node), played to its end,
// failed (why), and each frame it plays, after a seek or a step (the time)
typedef VideoEvents = {
	onLoaded:VideoNode,
	onEnded:VideoNode,
	onError:String,
	onTime:Float
}
