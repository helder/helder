package fixtures;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import Plain.*;

// The controls every accessibility adapter's test reads (MarkupCheck's
// accessFixture headless; LinuxAccessCheck, WinAccessCheck, MacAccessCheck,
// the phones' and the browser's in their windows): a label, a button, a
// checkbox, a slider, a field and a read-only one, a text area, a
// disclosure (expanded or not), a list of three items, a table (a header
// row and two rows of cells, the rows selectable), tabs, a live region and
// a scroll view whose last item starts out of sight (its identifier: id). The state the actions
// change is in its fields.
class AccessFixture implements Markup {
	public var saved = 0;
	public final checked = signal(false);
	public final volume = signal(0.5);
	public final name = signal("Ada");
	public final notes = signal("one\ntwo");
	public final open = signal(false);
	public final row = signal(0);
	public final tab = signal(0);
	public final status = signal("Ready");

	public function new() {}

	public function view():View
		return <view tag="fixture" padding={8} rowGap={4} alignItems="start">
			<text>Settings</text>
			<Button tag="save" label="Save" onPress={() -> saved++}/>
			<Checkbox tag="remember" checked={checked} label="Remember"/>
			<Slider tag="volume" value={volume} step={0.1} label="Volume"/>
			<field tag="name" value={name} placeholder="Name" aria-label="Name" onInput={e -> name(e.text)} width={120}/>
			<field tag="code" value={"X1"} readOnly aria-label="Code" width={60}/>
			<textarea tag="notes" value={notes} aria-label="Notes" onInput={e -> notes(e.text)} width={120}/>
			<button tag="more" aria-expanded={open} onPress={() -> open(o -> !o)}>More</button>
			<Show when={open}><text tag="extra">Extra</text></Show>
			<view tag="fruits" role="list" aria-label="Fruits" flexDirection="row" columnGap={6}>
				<view role="listitem">Apple</view><view role="listitem">Pear</view><view role="listitem">Plum</view>
			</view>
			<view tag="table" role="grid" aria-label="Mail">
				<view role="row" flexDirection="row" columnGap={6}><view role="columnheader">From</view><view role="columnheader">Subject</view></view>
				<Repeat count={2}>{i -> <view tag={"row" + i} role="row" flexDirection="row" columnGap={6} focusable aria-selected={() -> row() == i}
					onPress={_ -> row(i)}>
					<view role="cell">{["Ann", "Bob"][i]}</view><view role="cell">{["Hello", "Lunch"][i]}</view>
				</view>}</Repeat>
			</view>
			<view tag="tabs" role="tablist" flexDirection="row" columnGap={6}>
				<Repeat count={2}>{i -> <button role="tab" aria-selected={() -> tab() == i} onPress={() -> tab(i)}>{["General", "Advanced"][i]}</button>}</Repeat>
			</view>
			<view tag="status" aria-live="polite"><text>{status}</text></view>
			<view tag="scroller" id="scroller" overflow="scroll" height={20} width={80}>
				<text>First</text><text>Second</text><text tag="last">Last</text>
			</view>
		</view>;
}
