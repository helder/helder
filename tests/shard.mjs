// A zero-based shard index and total, shared by test drivers.
export function takeShard(args) {
	const at = args.indexOf('--shard');
	if (at === -1) return [0, 1];
	const [, spec] = args.splice(at, 2);
	const [index, total] = (spec ?? '').split('/').map(Number);
	if (!/^\d+\/[1-9]\d*$/.test(spec ?? '') || !Number.isSafeInteger(total) || index >= total || args.includes('--shard')) {
		throw new Error('--shard expects a zero-based index and total, for example --shard 0/2');
	}
	return [index, total];
}
