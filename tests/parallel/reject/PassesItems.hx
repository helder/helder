import helder.parallel.Items;
import helder.parallel.Parallel;

// an Items passed on from a body
function main() {
	var a = new Items<Float>(8);
	each(8, i -> a[i] = first(a));
}

function first(x:Items<Float>):Float
	return 0;
