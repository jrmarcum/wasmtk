interface Point {
    x: number;
    y: number;
}

interface Line {
    start: Point;
    end: Point;
}

function describePoint(p: Point): string {
    return `(${p.x}, ${p.y})`;
}

const p: Point = { x: 3.0, y: 4.0 };
const line: Line = { start: { x: 1.0, y: 2.0 }, end: { x: 5.0, y: 6.0 } };

// Direct struct arg — already works
console.log(describePoint(p));

// Pass struct field as arg (Phase 42 key feature)
console.log(describePoint(line.start));
console.log(describePoint(line.end));
