import helder.parallel.Items;
import helder.parallel.Parallel;

// a write at another index than the item's
function main() {
	var a = new Items<Float>(8);
	each(7, i -> a[i + 1] = 0);
}
