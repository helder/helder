package viewer;

import helder.story.Story;
import helder.ui.Node;
import helder.view.*;

// The browser and the viewer, at a laptop's size: the folder as a grid
// and as a list, dark and light; several selected; the inspector of a photo and of a PDF; a photo full size
// with its back pill, an error in its place, the status line; an empty
// folder, one that cannot be read, a search with no results (their trees
// in Viewer.story.snap)
final gridDark = story({name: "Browser/grid, dark", width: 1100, height: 700, render: c -> themed(browse(), true)});

final gridLight = story({name: "Browser/grid, light", width: 1100, height: 700, render: c -> themed(browse(), false)});

final listDark = story({name: "Browser/list, dark", width: 1100, height: 700, render: c -> themed(listed(), true)});

final listLight = story({name: "Browser/list, light", width: 1100, height: 700, render: c -> themed(listed(), false)});

final several = story({
	name: "Browser/several selected",
	width: 1100,
	height: 700,
	render: c -> {
		var x = browse();
		x.browser.select("alpha.png");
		x.browser.selection.extend(x.browser.indexOf("lossy.webp"));
		x.browser.selectionChanged();
		themed(x, true);
	}
});

final inspectorImage = story({
	name: "Browser/inspector, photo",
	width: 1100,
	height: 700,
	render: c -> {
		var x = browse();
		x.browser.select("photo 2.jpg");
		themed(x, true);
	}
});

final inspectorPdf = story({
	name: "Browser/inspector, PDF",
	width: 1100,
	height: 700,
	render: c -> {
		var x = Fixtures.explorer(["tests/fixtures/pdf"]);
		x.start("tests/fixtures/pdf");
		x.browser.select("pages.pdf");
		themed(x, true);
	}
});

final empty = story({
	name: "Browser/empty",
	width: 1100,
	height: 700,
	render: c -> {
		var x = new Explorer(new MemoryFiles().add("/empty/"), (_, _, _) -> {}, [], [], Preview.now);
		x.start("/empty");
		themed(x, true);
	}
});

final unreadable = story({
	name: "Browser/missing folder",
	width: 1100,
	height: 700,
	render: c -> {
		var x = new Explorer(new MemoryFiles().add("/here/"), (_, _, _) -> {}, [], [], Preview.now);
		x.start("/here/gone");
		themed(x, true);
	}
});

final noResults = story({
	name: "Browser/no results",
	width: 1100,
	height: 700,
	render: c -> {
		var x = browse();
		x.browser.searching(true);
		x.browser.search("puffin");
		themed(x, true);
	}
});

final fit = story({name: "Viewer/fit", width: 1100, height: 700, render: c -> themed(viewing("photo 2.jpg"), true)});

final error = story({name: "Viewer/error", width: 1100, height: 700, render: c -> themed(viewing("broken.jpg"), true)});

final status = story({
	name: "Viewer/status line",
	width: 1100,
	height: 700,
	render: c -> {
		var x = viewing("photo 2.jpg");
		x.viewer.statusOn(true);
		themed(x, true);
	}
});

// (the fixture folder browsed, decoded at once)
private function browse():Explorer {
	var x = Fixtures.explorer();
	x.start("tests/fixtures/folder");
	return x;
}

private function listed():Explorer {
	var x = browse();
	x.browser.layout(List);
	return x;
}

// (a file of it full size; the view's size in device pixels)
private function viewing(name:String):Explorer {
	var x = browse();
	x.viewer.camera.setView(1100, 648);
	x.open(name);
	return x;
}

// (the window's content, dark or light, at a laptop's size)
private function themed(x:Explorer, dark:Bool):View
	return Fixtures.themed(x, dark);
