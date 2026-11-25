// title: Video
// summary: A clip played by the system's decoders in a <video>: a tap plays and pauses it, the time beside
// tags: media, ui
import helder.asset.Asset;
import helder.media.MemorySource;
import helder.media.ui.VideoNode;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import helder.view.graph.Graph.*;

// A clip (embedded: its bytes in the program) shown by <video> as an image
// is, contained; it loops, muted, and a tap plays or pauses it. The
// controls are the program's: here its time and a button. (macOS and iOS:
// VideoToolbox and AudioToolbox; the browser: WebCodecs, muted so that it
// autoplays before a gesture; elsewhere the error is shown.)
class Clip implements Markup {
	static function main() {
		var node:Null<VideoNode> = null, time = signal("0.0 s"), error = signal("");
		UiWindow.run(<Surface title="Clip" width={480} height={320} background="#111111" dark={true}>
			<view flexGrow={1} padding={16} rowGap={12}>
				<video src={new MemorySource(Asset.embed("clip.mp4"))} flexGrow={1} autoPlay={true} loop={true} muted={true}
					onTime={t -> time(Std.string(Math.round(t * 10) / 10) + " s")} onError={e -> error(e)} ref={v -> node = v}/>
				<view flexDirection="row" columnGap={12} alignItems="center">
					<button padding="6 14" borderRadius={6} background="#27272a" color="#fafafa"
						onPress={() -> if (node != null) node.playing.peek() ? node.pause() : node.play()}>Play / pause</button>
					<text color="#a1a1aa">{time}</text>
					<text color="#fca5a5">{error}</text>
				</view>
			</view>
		</Surface>);
	}
}
