// A VirtualList's selected holds a key of its rows, by's: a signal of
// another type is an error (in Haxe: tests/view/reject/VirtualListKey.hx).
// expect: TS2322
import {render, signal} from "helder/view";
import {Node, VirtualList} from "helder/ui";

const rows = [{id: 1, name: "a"}], selected = signal<string | null>(null);
render(<view><VirtualList each={rows} by={r => r.id} selected={selected}>{(r, i) => <text>{r().name}</text>}</VirtualList></view>, new Node());
