// A store cleared (a screen built again) or let go: the timers and promise
// continuations set in it before are let go, none runs on the old store;
// what is set in it after runs
import { signal, flush } from "helder/view";
import { StoreProbe } from "./test-renderer";

const count = signal(0);
const a = new StoreProbe("a"), b = new StoreProbe("b");
let resolveLater: (v: number) => void = () => {};
const later = new Promise<number>(r => { resolveLater = r; });
let ticks = 0;

a.run(() => {
	later.then(() => console.log("continuation set before the clear: must not run"));
	setInterval(() => {
		ticks++;
		count(c => c + 1);
		flush();
		console.log("old tick", ticks, count());
		if (ticks === 2) {
			a.clear();
			console.log("cleared");
			a.run(() => {
				let fresh = 0;
				const id = setInterval(() => {
					fresh++;
					count(c => c + 10);
					flush();
					console.log("new tick", fresh, count());
					if (fresh === 3) clearInterval(id);
				}, 5);
			});
		}
	}, 5);
});
b.run(() => {
	setInterval(() => console.log("b's interval after it was let go: must not run"), 5);
});
b.dispose();
setTimeout(() => {
	resolveLater(1);
	setTimeout(() => {
		let inA = -1;
		a.run(() => { inA = count(); });
		console.log("default", count(), "a", inA);
		a.dispose();
	}, 10);
}, 60);
