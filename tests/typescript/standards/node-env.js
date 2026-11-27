// process.env.NODE_ENV as a bundler makes it (immer's checks): the build's
// mode, with no process global; a binding of its own named process is its
function check(ok, what) {
	if (!ok) throw new Error(what);
}
check(process.env.NODE_ENV === "production", "process.env.NODE_ENV: " + process.env.NODE_ENV);
check(typeof process === "undefined", "a process global");
{
	const process = {env: {NODE_ENV: "mine"}};
	check(process.env.NODE_ENV === "mine", "a local process");
}
console.log("ok");
