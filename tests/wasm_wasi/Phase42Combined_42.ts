// Phase 42 Combined: string-returning functions + nested struct literals + chained field access

interface Point {
    x: number;
    y: number;
}

interface Segment {
    from: Point;
    to: Point;
}

function describePoint(p: Point): string {
    return `(${p.x},${p.y})`;
}

function addCoords(a: Point, b: Point): string {
    return `sum=(${a.x + b.x},${a.y + b.y})`;
}

const origin: Point = { x: 0.0, y: 0.0 };
const p1: Point = { x: 3.0, y: 4.0 };
const seg: Segment = { from: { x: 1.0, y: 2.0 }, to: { x: 7.0, y: 8.0 } };

// String-returning functions
console.log(describePoint(origin));
console.log(describePoint(p1));

// Pass nested struct field as function argument
console.log(describePoint(seg.from));
console.log(describePoint(seg.to));

// Chained field access in console.log args
console.log(seg.from.x);
console.log(seg.to.y);

// Combine string return + struct fields
console.log(addCoords(seg.from, seg.to));

// Chained access in template literal
const msg: string = `from=${describePoint(seg.from)} to=${describePoint(seg.to)}`;
console.log(msg);
