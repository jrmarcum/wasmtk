const PI: number = 3.141592653589793;

interface Geometry {
    kind: string;
    val1: number;
    val2: number;
}

function newRect(w: number, h: number): Geometry {
    return { kind: "rect", val1: w, val2: h };
}

function newCircle(r: number): Geometry {
    return { kind: "circle", val1: r, val2: 0 };
}

function area(g: Geometry): number {
    if (g.kind === "rect") return g.val1 * g.val2;
    if (g.kind === "circle") return PI * g.val1 * g.val1;
    return 0;
}

function perim(g: Geometry): number {
    if (g.kind === "rect") return 2 * g.val1 + 2 * g.val2;
    if (g.kind === "circle") return 2 * PI * g.val1;
    return 0;
}

function geomStr(g: Geometry): string {
    if (g.kind === "rect") return `{${g.val1} ${g.val2}}`;
    if (g.kind === "circle") return `{${g.val1}}`;
    return "{}";
}

function measure(g: Geometry): void {
    console.log(geomStr(g));
    console.log(area(g));
    console.log(perim(g));
}

const r: Geometry = newRect(3, 4);
const c: Geometry = newCircle(5);

measure(r);
measure(c);
