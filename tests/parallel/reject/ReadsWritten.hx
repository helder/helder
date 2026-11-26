import helder.parallel.Items;
import helder.parallel.Parallel;

// an Items written at i, read at another index
function main() {
	var a = new Items<Float>(8);
	each(8, i -> {
		var next = a[(i + 1) % 8];
		a[i] = next;
	});
}
