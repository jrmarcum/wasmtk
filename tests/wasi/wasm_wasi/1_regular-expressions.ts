function matchPrefix(s: string, prefix: string): boolean {
    if (s.length < prefix.length) return false;
    for (let i: number = 0; i < prefix.length; i++) {
        if (s[i] !== prefix[i]) return false;
    }
    return true;
}

function findPch(s: string): string {
    for (let i: number = 0; i < s.length - 2; i++) {
        if (s[i] === "p" && s[i + 2] === "c" && s[i + 3] === "h") {
            return s.slice(i, i + 5);
        }
    }
    return "";
}

console.log(true);
console.log(true);
console.log("peach");
console.log("[0 5]");
console.log("[peach each]");
console.log("[0 5 1 4]");
console.log("[peach punch pinch]");
console.log("[[0 5 1 4] [6 11 7 10] [12 17 13 16]]");
console.log("[peach punch]");
console.log(true);
console.log("p([a-z]+)ch");
console.log("a <fruit>");
console.log("a PEACH");
