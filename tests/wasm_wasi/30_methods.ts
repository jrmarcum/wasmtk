interface Rect {
    width: number;
    height: number;
}

function newRect(width: number, height: number): Rect {
    return { width, height };
}

function area(r: Rect): number {
    return r.width * r.height;
}

function perim(r: Rect): number {
    return 2 * r.width + 2 * r.height;
}

const r: Rect = newRect(10, 5);
console.log("area:", area(r));
console.log("perim:", perim(r));
