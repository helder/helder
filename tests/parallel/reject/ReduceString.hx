import helder.parallel.Items;
import helder.parallel.Parallel;

// a reduction of what is no Int or Float
function main() {
	var a = new Items<Float>(8);
	var lowest = min(8, i -> a[i] > 0);
}
