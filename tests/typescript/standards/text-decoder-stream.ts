function check(): void {
    try {
        new globalThis.TextDecoder().decode(new Uint8Array([65]), {stream: true});
    } catch (e) {
        if (e instanceof TypeError && e.message.includes("stream")) return;
        throw e;
    }
    throw new Error("TextDecoder accepted streaming");
}
check();
