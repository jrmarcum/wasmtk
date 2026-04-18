// Phase 27: Extended string methods
// Tests: trim, trimStart, trimEnd, charCodeAt, charAt, startsWith, endsWith,
//        toUpperCase, toLowerCase, replace, replaceAll, padStart, padEnd, repeat, split

function testTrim(): void {
  const s: string = "  hello world  ";
  const trimmed: string = s.trim();
  console.log(trimmed);

  const s2: string = "  leading";
  const ts: string = s2.trimStart();
  console.log(ts);

  const s3: string = "trailing  ";
  const te: string = s3.trimEnd();
  console.log(te);
}

function testCharCodeAt(): void {
  const s: string = "ABC";
  const code: i32 = s.charCodeAt(0);
  console.log(code);

  const code2: i32 = s.charCodeAt(1);
  console.log(code2);

  const code3: i32 = s.charCodeAt(2);
  console.log(code3);
}

function testCharAt(): void {
  const s: string = "hello";
  const c: string = s.charAt(1);
  console.log(c);

  const c2: string = s.charAt(4);
  console.log(c2);
}

function testStartsEndsWith(): void {
  const s: string = "hello world";
  const sw1: i32 = s.startsWith("hello");
  console.log(sw1);

  const sw2: i32 = s.startsWith("world");
  console.log(sw2);

  const ew1: i32 = s.endsWith("world");
  console.log(ew1);

  const ew2: i32 = s.endsWith("hello");
  console.log(ew2);
}

function testCaseConversion(): void {
  const s: string = "Hello World";
  const up: string = s.toUpperCase();
  console.log(up);

  const lo: string = s.toLowerCase();
  console.log(lo);
}

function testReplace(): void {
  const s: string = "foo bar foo";
  const r1: string = s.replace("foo", "baz");
  console.log(r1);

  const r2: string = s.replaceAll("foo", "baz");
  console.log(r2);
}

function testPad(): void {
  const s: string = "42";
  const ps: string = s.padStart(5, "0");
  console.log(ps);

  const pe: string = s.padEnd(5, ".");
  console.log(pe);
}

function testRepeat(): void {
  const s: string = "ab";
  const r: string = s.repeat(3);
  console.log(r);

  const s2: string = "x";
  const r2: string = s2.repeat(1);
  console.log(r2);
}

function testSplit(): void {
  const s: string = "a,b,c";
  const parts: string[] = s.split(",");
  const count: i32 = parts.length;
  console.log(count);

  for (const part of parts) {
    console.log(part);
  }

  const s2: string = "hello world foo";
  const words: string[] = s2.split(" ");
  for (const w of words) {
    console.log(w);
  }
}

testTrim();
testCharCodeAt();
testCharAt();
testStartsEndsWith();
testCaseConversion();
testReplace();
testPad();
testRepeat();
testSplit();
