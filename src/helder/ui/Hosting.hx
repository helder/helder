package helder.ui;

import helder.view.RootView;

// A preview host's way into a program's main (helder.scenario): while it is
// set, UiWindow.run opens no window and does not block, handing its content
// to run, and each <Surface> gives its props (its title and size, its
// children) to surface instead of opening one. helder run and Play never
// set it
class Hosting {
	public static var current:Null<Hosting> = null;

	public final run:RootView->Void;
	public final surface:UiWindow.SurfaceProps->Void;

	public function new(run:RootView->Void, surface:UiWindow.SurfaceProps->Void) {
		this.run = run;
		this.surface = surface;
	}
}
