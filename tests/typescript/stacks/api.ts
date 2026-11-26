// an error in a callback helder's API calls (a signal's update): its frames
// the program's, helder's between them one line
import { signal } from "helder/view";

const count = signal(1);

function bump(by: number) {
	count(n => {
		if (n + by > 2) throw new RangeError("too many: " + (n + by));
		return n + by;
	});
}

bump(1);
try {
	bump(1);
} catch (e) {
	console.log((e as Error).stack);
}
console.log(count());
