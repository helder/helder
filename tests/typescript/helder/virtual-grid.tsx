// VirtualGrid's markup, its ref and the Selection it exposes.
import { Key, Selection, VirtualGrid, GridScroll, VirtualList } from "helder/ui";
import { Read, render, signal } from "helder/view";
import { UiProbe } from "./ui-probe";

const files = signal(["Alpha", "Beta", "Cedar", "Delta", "Elm", "Fir"]);
const selection = new Selection(i => files()[i], () => files().length);
let grid: GridScroll | null = null;
const mounted = () => grid;
const root = UiProbe.root(240, 140);
render(
	<VirtualGrid each={files} by={s => s} cellWidth={70} cellHeight={20} padding={8}
		selection={selection} textOf={s => s} ref={n => { grid = n; }}
		onActivate={indices => console.log("grid activate", indices.join(","))}>{
		(file: Read<string>, i: number) => <text tag={"file-" + i}>{file()}</text>
	}</VirtualGrid>,
	root
);
UiProbe.click("file-0");
UiProbe.key(Key.DOWN, ["shift"]);
console.log(mounted()?.columns, mounted()?.selection.keys().join(","));
UiProbe.key(Key.ENTER);
mounted()?.focusIndex(2);
console.log(selection.focus, selection.focusIndex());
UiProbe.type("f");
console.log(selection.keys().join(","));

const list = new Selection(i => files()[i], () => files().length);
render(
	<VirtualList each={files} by={s => s} itemHeight={20} selection={list}
		onActivate={indices => console.log("list activate", indices.join(","))}>{
		(file: Read<string>, i: number) => <text tag={"row-" + i}>{file()}</text>
	}</VirtualList>,
	UiProbe.root(240, 140)
);
UiProbe.click("row-1");
UiProbe.key(Key.DOWN, ["shift"]);
UiProbe.key(Key.ENTER);

render(
	<VirtualList each={files} itemHeight={20} onActivate={rows => console.log("row activate", files()[rows[0]].toUpperCase())}>{
		(file: Read<string>, i: number) => <text tag={"plain-" + i}>{file()}</text>
	}</VirtualList>,
	UiProbe.root(240, 140)
);
UiProbe.click("plain-2");
UiProbe.key(Key.ENTER);
