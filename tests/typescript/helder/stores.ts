// A timer and a promise's continuation set in a store run in that store
// (helder.view.graph.Atoms: Promises' Reaction and Timer keep it): what they
// write is the store's, the default's untouched; a timer set at the top
// level runs in the default
import { signal, flush } from "helder/view";
import { StoreProbe } from "./test-renderer";

const count = signal(0);
const a = new StoreProbe("a");

function inA(): number {
	let v = -1;
	a.run(() => { v = count(); });
	return v;
}

a.run(() => {
	Promise.resolve(1).then(n => {
		count(n);
		flush();
		console.log("promise wrote", count());
	});
	setTimeout(() => {
		count(c => c + 10);
		flush();
		console.log("timer wrote", count());
	}, 5);
});
setTimeout(() => {
	console.log("default", count(), "a", inA());
	a.dispose();
}, 20);
