import helder.parallel.Items;
import helder.parallel.Parallel;

// a captured local assigned in a body
function main() {
	var a = new Items<Float>(8), total = 0.0;
	each(8, i -> total += a[i]);
}
