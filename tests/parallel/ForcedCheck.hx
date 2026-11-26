import helder.parallel.Items;
import helder.parallel.Parallel;

// HELDER_PARALLEL forcing every call (the parallel lane runs it with each
// value): Parallel.log prints the form the site took
function main() {
	Parallel.log = true;
	var a = new Items<Float>(100);
	each(100, i -> a[i] = i * 2);
	if (a[99] != 198) throw "each: " + a[99];
	var s = sum(100, i -> a[i]);
	if (s != 9900) throw "sum: " + s;
}
