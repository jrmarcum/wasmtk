function mayPanic(): void {
    throw new Error("a problem");
}

function safeDiv(): void {
    try {
        mayPanic();
        console.log("After mayPanic()");
    } catch (r) {
        const msg: string = r instanceof Error ? r.message : `${r}`;
        console.log("Recovered. Error:\n", msg);
    }
}

safeDiv();
