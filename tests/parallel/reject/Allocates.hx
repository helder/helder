import helder.parallel.Items;
import helder.parallel.Parallel;

// an allocation in a body
function main() {
	var a = new Items<Float>(8);
	each(8, i -> {
		var xs = [1.0, 2.0];
		a[i] = xs[0];
	});
}
