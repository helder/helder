import helder.parallel.Items;
import helder.parallel.Parallel;

// the index assigned
function main() {
	var a = new Items<Float>(8);
	each(8, i -> {
		i = 0;
		a[i] = 1;
	});
}
