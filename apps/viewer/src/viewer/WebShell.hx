package viewer;

import helder.os.Settings;

#if (hxmc.target == "wasm32-wasi")
import helder.async.Async;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;

// The viewer in a browser (viewer.helder.run): the page is its window. It
// opens on the sample folder (Samples, bundled beside the page); Open
// folder shows one of the user's where the browser can pick one (the File
// System Access API: Chromium's; helder.os.Folders), and a folder or
// files dropped on the page (WebFolders' own) are shown the same way, each
// a place of the sidebar's by its name (Shell.addFolder, showFolder).
// Read only, in the browser alone (WebFiles): no trash, no system apps, no
// drag out, no second window to hand files to. The decodes, previews and
// thumbnails (kept in memory: Tiles) are helder.jobs' jobs in Web Workers,
// of bytes read on the page.
@:renderer(helder.ui.view.NodeRenderer)
class WebShell implements Markup {
	public static function main() {
		var files = new WebFiles();
		var x = new Explorer(files, (path, side, done) -> Async.launch(_ -> done(Decode.read(files, path, side))),
			[{kind: Pictures, name: Samples.ROOT, path: Samples.ROOT}], [], (path, done) -> Preview.read(files, path, done),
			(path, done) -> Async.launch(_ -> done(PdfPages.read(files, path))));
		var viewer = x.viewer;
		viewer.mod = helder.ui.actions.Keymap.mac ? "Cmd" : "Ctrl";
		x.thumbnails = new Thumbnails(files);
		helder.ui.menu.Menus.appName = "Viewer";
		ViewerActions.defaults(helder.ui.actions.Keymap.global);
		if (helder.os.Folders.available()) x.openFolder = () -> Shell.addFolder(x, files.grants);
		viewer.openDialog = () -> if (x.openFolder != null) x.openFolder();
		helder.os.web.WebFolders.onDrop(g -> Shell.showFolder(x, files.grants, g));
		x.browser.go(Samples.ROOT);
		UiWindow.run(<Surface title={() -> x.full() ? viewer.title() : x.sidebar.title(x.browser.dir())}
			scrollbars="overlay" background={() -> "#" + StringTools.hex(ViewerView.canvas(Settings.dark()), 6)} ref={w -> {
				Shell.attach(w.ui.root, x);
				helder.view.graph.Graph.effect(() -> viewer.fullscreen(), on -> w.window.fullscreen = on);
			}}>
			{Shell.view(x)}
		</Surface>);
	}
}
#end
