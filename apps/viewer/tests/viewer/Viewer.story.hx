package viewer;

import helder.story.Story;
import helder.ui.Node;
import helder.view.*;

// The browser and the viewer, at a laptop's size: the folder as a grid
// and as a list, dark and light; several selected; a PDF's column scrolled
// between two pages; the inspector of a photo, of a PDF and of a Markdown
// document; a marquee being dragged over the grid; the search field
// focused, dark and light; an error in a photo's place, the status line;
// an empty folder, one that cannot be read, a search with no results (their
// trees in Viewer.story.snap). A photo full size and a Markdown document,
// dark and light, are Viewer.scenario.hx's (the program's own Window)
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

// (a marquee dragged from under the cells up over the first row, as a mouse would: its band in the look's accent)
final marquee = story({
	name: "Browser/marquee",
	width: 1100,
	height: 700,
	render: c -> {
		c.settled(false);
		Fixtures.marquee(browse(), () -> c.settled(true));
	}
});

// (the search field focused: one ring round its box, Look's composite field's)
final searchDark = story({
	name: "Browser/search focused, dark",
	width: 1100,
	height: 700,
	render: c -> {
		var x = browse();
		x.browser.searching(true);
		themed(x, true);
	}
});

final searchLight = story({
	name: "Browser/search focused, light",
	width: 1100,
	height: 700,
	render: c -> {
		var x = browse();
		x.browser.searching(true);
		themed(x, false);
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

final error = story({name: "Viewer/error", width: 1100, height: 700, render: c -> themed(viewing("broken.jpg"), true)});

final pdf = story({
	name: "Viewer/PDF, between two pages",
	width: 1100,
	height: 700,
	render: c -> {
		var x = Fixtures.explorer(["tests/fixtures/pdf"]);
		x.start("tests/fixtures/pdf/pages.pdf");
		var doc = x.viewer.document();
		// (the stage's size, below the bar; page 2's top a third of the way down)
		doc.view(1100, 648);
		doc.goTo(1);
		doc.screens(-0.3);
		themed(x, true);
	}
});

final inspectorMarkdown = story({
	name: "Browser/inspector, a Markdown document",
	width: 1100,
	height: 700,
	render: c -> {
		var x = Fixtures.samples();
		x.browser.go(Samples.ROOT);
		x.browser.inspector(true);
		x.browser.select("Welcome.md");
		themed(x, false);
	}
});

// (the sidebar at a level of a volume: its capacity card at the foot)
final capacity = story({
	name: "Browser/sidebar's volume",
	width: 1100,
	height: 700,
	render: c -> {
		var x = Fixtures.explorer(null, [Fixtures.DISK]);
		x.start("tests/fixtures/folder");
		themed(x, false);
	}
});

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
