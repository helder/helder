import helder.parallel.Items;
import helder.parallel.Parallel;

// a kernel reading a local
function main() {
	var scale = 2.0;
	final K = kernel(function(i:Int, p:{to:Items<Float>}) {
		p.to[i] = scale;
	});
}
