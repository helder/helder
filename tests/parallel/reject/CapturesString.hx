import helder.parallel.Items;
import helder.parallel.Parallel;

// a capture of a type a body has no lanes of
function main() {
	var a = new Items<Float>(8), names = ["x"];
	each(8, i -> a[i] = names.length);
}
