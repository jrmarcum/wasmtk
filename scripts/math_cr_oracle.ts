// Reusable correctly-rounded (CR) oracle + double-double (dd) harness for the mathlib CR sweep.
// See cmem/math-cr-sweep.md. Import these to validate a mathlib function's wasm output against the
// IEEE-754 correctly-rounded reference. Add new-function oracles following the templates below.
//
// Usage sketch (per function): generate a wasic program printing Math.fn(id(v)) for a battery of v,
// `wasmtk run` the .wasm, then compare each printed line to fnOracle(v). Require 100% (0 off).

export const P = 400n;
export const SCALE = 1n << P;
const dv = new DataView(new ArrayBuffer(8));

export function bits(x: number): bigint { dv.setFloat64(0, x); return dv.getBigUint64(0); }
export function ulp(a: number, b: number): number {
  if (a === b) return 0;
  if (!isFinite(a) && !isFinite(b)) return a === b ? 0 : 1e18;
  if (!isFinite(a) || !isFinite(b)) return 1e18;
  const d = bits(a) - bits(b); return Number(d < 0n ? -d : d);
}

// exact value of double x as a scaled BigInt (value * 2^P)
export function toBig(x: number): bigint {
  dv.setFloat64(0, x); const b = dv.getBigUint64(0);
  const sign = (b >> 63n) ? -1n : 1n; const exp = Number((b >> 52n) & 0x7ffn);
  let mant = b & 0xfffffffffffffn; let e2: number, m: bigint;
  if (exp === 0) { m = mant; e2 = -1074; } else { m = mant + (1n << 52n); e2 = exp - 1075; }
  const sc = (e2 + Number(P) >= 0) ? m << BigInt(e2 + Number(P)) : m >> BigInt(-(e2 + Number(P)));
  return sign * sc;
}

// correctly round a * 2^e to the nearest double (round-to-even); handles subnormal + overflow.
export function roundScaled(a: bigint, e: number): number {
  if (a === 0n) return 0; const neg = a < 0n; if (neg) a = -a;
  const bl = a.toString(2).length; const msbExp = bl - 1 + e;
  if (msbExp > 1023) return neg ? -Infinity : Infinity;
  let keep = msbExp >= -1022 ? 53 : 53 - (-1022 - msbExp);
  if (keep < 1) { // below the smallest subnormal
    const cmpExp = -1075 - e; if (cmpExp < 0) return neg ? -Number.MIN_VALUE : Number.MIN_VALUE;
    const thr = 1n << BigInt(cmpExp); if (a > thr) return neg ? -Number.MIN_VALUE : Number.MIN_VALUE;
    return neg ? -0 : 0;
  }
  const drop = bl - keep; let mant: bigint, resExp: number;
  if (drop > 0) {
    const half = 1n << BigInt(drop - 1); const low = a & ((1n << BigInt(drop)) - 1n);
    mant = a >> BigInt(drop); if (low > half || (low === half && (mant & 1n) === 1n)) mant += 1n;
    resExp = e + drop;
  } else { mant = a << BigInt(-drop); resExp = e + drop; }
  const val = Number(mant) * Math.pow(2, resExp); return neg ? -val : val;
}

// decompose x>0 into m in [1,2) and e (subnormal-safe): x = m * 2^e
export function decomp(x: number): { m: number; e: number } {
  dv.setFloat64(0, x); let b = dv.getBigUint64(0); let exp = Number((b >> 52n) & 0x7ffn); let e: number;
  if (exp === 0) { x *= 2 ** 54; dv.setFloat64(0, x); b = dv.getBigUint64(0); exp = Number((b >> 52n) & 0x7ffn); e = exp - 1023 - 54; }
  else e = exp - 1023;
  const mb = (b & 0x800fffffffffffffn) | 0x3ff0000000000000n; dv.setBigUint64(0, mb);
  return { m: dv.getFloat64(0), e };
}

// ---- double-double (dd) ops (Veltkamp two-product; matches the WAT $__* helpers) ----
const SPLIT = 134217729.0; // 2^27 + 1
export type DD = [number, number];
export function twoProd(a: number, b: number): DD { const p = a * b; let c = SPLIT * a; const ah = c - (c - a), al = a - ah; c = SPLIT * b; const bh = c - (c - b), bl = b - bh; return [p, ((ah * bh - p) + ah * bl + al * bh) + al * bl]; }
export function twoSum(a: number, b: number): DD { const s = a + b, bb = s - a, e = (a - (s - bb)) + (b - bb); return [s, e]; }
export function ddAdd(a: DD, b: DD): DD { let [s, e] = twoSum(a[0], b[0]); e += a[1] + b[1]; return twoSum(s, e); }
export function ddMul(a: DD, b: DD): DD { let [p, e] = twoProd(a[0], b[0]); e += a[0] * b[1] + a[1] * b[0]; return twoSum(p, e); }
export function ddMulD(a: DD, b: number): DD { let [p, e] = twoProd(a[0], b); e += a[1] * b; return twoSum(p, e); }
export function ddRecipInt(d: number): DD { const h = 1 / d; const [p, e] = twoProd(h, d); const res = ((1 - p) - e); return twoSum(h, res * h); }
export function ddDiv(a: DD, b: DD): DD { const q1 = a[0] / b[0]; let r = ddAdd(a, ddMulD(b, -q1)); const q2 = r[0] / b[0]; r = ddAdd(r, ddMulD(b, -q2)); const q3 = r[0] / b[0]; let [h, l] = twoSum(q1, q2); l += q3; return twoSum(h, l); }

// scalbn(x, n) = x*2^n, correctly rounded (musl-style). Matches WAT $__scalbn.
export function scalbn(x: number, n: number): number {
  let y = x;
  if (n > 1023) { y *= 2 ** 1023; n -= 1023; if (n > 1023) { y *= 2 ** 1023; n -= 1023; if (n > 1023) n = 1023; } }
  else if (n < -1022) { y *= (2 ** -1022) * (2 ** 53); n += 1022 - 53; if (n < -1022) { y *= (2 ** -1022) * (2 ** 53); n += 1022 - 53; if (n < -1022) n = -1022; } }
  return y * (2 ** n);
}

// crRound(hi, lo, k) = correctly-rounded (hi+lo)*2^k. Matches WAT $__cr.
export function crRound(hi: number, lo: number, k: number): number {
  if (hi === 0) return 0; const neg = hi < 0; if (neg) { hi = -hi; lo = -lo; }
  const eh = Math.floor(Math.log2(hi)); if (eh + k > 1023) return neg ? -Infinity : Infinity;
  const probe = scalbn(hi, k); let val: number;
  if (probe >= 2.2250738585072014e-308) { val = scalbn(hi + lo, k); } // normal: round-then-scale
  else { // subnormal: round (hi+lo)*2^(k+1074) to nearest even integer, then *2^-1074
    const j = k + 1074; let whi = scalbn(hi, j), wlo = scalbn(lo, j);
    let fl = Math.floor(whi); let frac = (whi - fl) + wlo;
    while (frac >= 1) { frac -= 1; fl += 1; } while (frac < 0) { frac += 1; fl -= 1; }
    let m: number; if (frac > 0.5) m = fl + 1; else if (frac < 0.5) m = fl; else m = (fl % 2 === 0) ? fl : fl + 1;
    val = m * Math.pow(2, -1074);
  }
  return neg ? -val : val;
}

// high-precision constants (as scaled BigInt) — extend as needed
function d2s(s: string): bigint { const neg = s[0] === "-"; if (neg) s = s.slice(1); const [ip, fp = ""] = s.split("."); const d = BigInt(ip + fp); const den = 10n ** BigInt(fp.length); const v = (d * SCALE + den / 2n) / den; return neg ? -v : v; }
export const LN2 = d2s("0.693147180559945309417232121458176568075500134360255254120680009493393621969694715605863326996418688");
export const LN10 = d2s("2.302585092994045684017991454684364207601101488628772976033327900967572609677352480235997205089598298");
export const PI = d2s("3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117068");
export const TWO_PI = PI * 2n;
export const SQRT2 = d2s("1.4142135623730950488016887242096980785696718753769");

// ---- correctly-rounded oracles for the DONE functions (templates for new ones) ----
export function expOracle(x: number): number {
  if (x !== x) return NaN; if (x === Infinity) return Infinity; if (x === -Infinity) return 0;
  const xs = toBig(x); let k = (xs * 2n + (xs >= 0n ? LN2 : -LN2)) / (2n * LN2); let r = xs - k * LN2;
  let term = SCALE, sum = SCALE; for (let n = 1n; n < 80n; n++) { term = (term * r) >> P; term = term / n; sum += term; if (term < 2n && term > -2n) break; }
  return roundScaled(sum, Number(k) - Number(P));
}
function logScaled(x: number): bigint { let { m, e } = decompBig(x); if (m >= SQRT2big) { m >>= 1n; e += 1; } const s = ((m - SCALE) * SCALE) / (m + SCALE); return BigInt(e) * LN2 + atanh2(s); }
function decompBig(x: number): { m: bigint; e: number } { dv.setFloat64(0, x); const b = dv.getBigUint64(0); const exp = Number((b >> 52n) & 0x7ffn); let mant = b & 0xfffffffffffffn; let e2: number, mm: bigint; if (exp === 0) { mm = mant; e2 = -1074; } else { mm = mant + (1n << 52n); e2 = exp - 1075; } const bl = mm.toString(2).length; const e = e2 + bl - 1; const shift = Number(P) - (bl - 1); const m = shift >= 0 ? mm << BigInt(shift) : mm >> BigInt(-shift); return { m, e }; }
const SQRT2big = SQRT2;
function atanh2(s: bigint): bigint { const s2 = (s * s) >> P; let term = s, sum = s; for (let k = 1n; k < 200n; k++) { term = (term * s2) >> P; const add = term / (2n * k + 1n); sum += add; if (add < 2n && add > -2n) break; } return sum * 2n; }
function roundBig(total: bigint): number { const neg = total < 0n; let a = neg ? -total : total; if (a === 0n) return 0; const bl = a.toString(2).length; const e2 = bl - 1 - Number(P); const drop = bl - 53; let mm: bigint, re: number; if (drop > 0) { const h = 1n << BigInt(drop - 1); const lo = a & ((1n << BigInt(drop)) - 1n); mm = a >> BigInt(drop); if (lo > h || (lo === h && (mm & 1n) === 1n)) mm += 1n; re = e2 - 52; if (mm >= (1n << 53n)) { mm >>= 1n; re += 1; } } else { mm = a << BigInt(-drop); re = e2 - 52; } const v = Number(mm) * Math.pow(2, re); return neg ? -v : v; }
export const logOracle = (x: number) => x === 1 ? 0 : x === 0 ? -Infinity : x < 0 ? NaN : !isFinite(x) ? x : roundBig(logScaled(x));
export const log2Oracle = (x: number) => x === 1 ? 0 : x === 0 ? -Infinity : x < 0 ? NaN : !isFinite(x) ? x : roundBig((logScaled(x) * SCALE) / LN2);
export const log10Oracle = (x: number) => x === 1 ? 0 : x === 0 ? -Infinity : x < 0 ? NaN : !isFinite(x) ? x : roundBig((logScaled(x) * SCALE) / LN10);
export function cbrtOracle(x: number): number { if (x !== x) return NaN; if (x === 0) return x; if (!isFinite(x)) return x; const neg = x < 0; const a = Math.abs(x); const { m, e } = decomp(a); const q = Math.floor(e / 3); const s = e - 3 * q; const w = m * (2 ** s); const W = toBig(w); const W3 = W << (2n * P); let Y = toBig(Math.cbrt(w)); for (let it = 0; it < 200; it++) { const nY = (2n * Y + W3 / (Y * Y)) / 3n; const d = nY > Y ? nY - Y : Y - nY; Y = nY; if (d <= 1n) break; } const r = roundScaled(Y, q - Number(P)); return neg ? -r : r; }
// sin/cos/tan oracle: reduce mod 2*pi in fixed-point, Taylor.
function trigReduce(x: number): bigint { let r = ((toBig(x) % TWO_PI) + TWO_PI) % TWO_PI; if (r > PI) r -= TWO_PI; return r; }
function scSin(r: bigint): bigint { const r2 = (r * r) >> P; let t = r, s = r; for (let k = 1n; k < 90n; k++) { t = (t * r2) >> P; t = -t / ((2n * k) * (2n * k + 1n)); s += t; if (t > -2n && t < 2n) break; } return s; }
function scCos(r: bigint): bigint { const r2 = (r * r) >> P; let t = SCALE, s = SCALE; for (let k = 1n; k < 90n; k++) { t = (t * r2) >> P; t = -t / ((2n * k - 1n) * (2n * k)); s += t; if (t > -2n && t < 2n) break; } return s; }
export const sinOracle = (x: number) => !isFinite(x) ? NaN : roundScaled(scSin(trigReduce(x)), -Number(P));
export const cosOracle = (x: number) => !isFinite(x) ? NaN : roundScaled(scCos(trigReduce(x)), -Number(P));
export const tanOracle = (x: number) => !isFinite(x) ? NaN : roundScaled((scSin(trigReduce(x)) * SCALE) / scCos(trigReduce(x)), -Number(P));

// atan: two-stage reduction (complement 1/z, mid (z-1)/(z+1)) into |z|<=tan(pi/8), then series.
const PI4 = PI / 4n, PI2 = PI / 2n, TANPI8 = SQRT2 - SCALE;
function atanSeries(A: bigint): bigint {
  const A2 = (A * A) >> P; let term = A, sum = A;
  for (let k = 1n; k < 400n; k++) { term = (term * A2) >> P; const add = (k % 2n === 1n ? -term : term) / (2n * k + 1n); sum += add; if (add < 2n && add > -2n) break; }
  return sum;
}
export function atanOracle(x: number): number {
  if (x !== x) return NaN;
  if (x === Infinity) return Math.PI / 2; if (x === -Infinity) return -Math.PI / 2;
  if (x === 0) return x;
  if (Math.abs(x) < 7.450580596923828e-9) return x; // 2^-27: atan(x)===x; toBig would underflow
  const neg = x < 0; let A = toBig(x); if (A < 0n) A = -A;
  let comp = false, mid = false;
  if (A > SCALE) { A = (SCALE * SCALE) / A; comp = true; }
  if (A > TANPI8) { A = ((A - SCALE) * SCALE) / (A + SCALE); mid = true; }
  let R = atanSeries(A);
  if (comp && mid) R = PI4 - R; else if (comp) R = PI2 - R; else if (mid) R = PI4 + R;
  const val = roundScaled(R, -Number(P)); return neg ? -val : val;
}

// asin/acos/atan2 correctly-rounded oracles (fixed-point): reduce to atan of a scaled value.
function isqrtBig(n: bigint): bigint { if (n < 2n) return n; let x = n, y = (x + 1n) >> 1n; while (y < x) { x = y; y = (x + n / x) >> 1n; } return x; }
const sqrtFx = (v: bigint) => isqrtBig(v << P); // sqrt(v/2^P) * 2^P
function atanFxSigned(A: bigint): bigint { // scaled atan of a scaled value (any sign/magnitude)
  const neg = A < 0n; if (neg) A = -A; let comp = false, mid = false;
  if (A > SCALE) { A = (SCALE * SCALE) / A; comp = true; }
  if (A > TANPI8) { A = ((A - SCALE) * SCALE) / (A + SCALE); mid = true; }
  let R = atanSeries(A);
  if (comp && mid) R = PI4 - R; else if (comp) R = PI2 - R; else if (mid) R = PI4 + R;
  return neg ? -R : R;
}
export function asinOracle(x: number): number {
  if (x !== x) return NaN; if (Math.abs(x) > 1) return NaN;
  if (x === 1) return Math.PI / 2; if (x === -1) return -Math.PI / 2; if (x === 0) return x;
  const neg = x < 0, A = toBig(Math.abs(x));
  const t = (A << P) / sqrtFx(SCALE - ((A * A) >> P)); // (a/sqrt(1-a^2))*2^P
  const val = roundScaled(atanFxSigned(t), -Number(P)); return neg ? -val : val;
}
export function acosOracle(x: number): number {
  if (x !== x) return NaN; if (Math.abs(x) > 1) return NaN;
  if (x === 1) return 0; if (x === -1) return roundScaled(PI, -Number(P));
  const X = toBig(x);
  const R = atanFxSigned(sqrtFx(((SCALE - X) << P) / (SCALE + X))); // 2*atan(sqrt((1-x)/(1+x)))
  return roundScaled(2n * R, -Number(P));
}
export function atan2Oracle(y: number, x: number): number {
  if (x !== x || y !== y) return NaN;
  const piCR = roundScaled(PI, -Number(P)), pi2 = Math.PI / 2;
  if (!isFinite(x) || !isFinite(y)) {
    if (!isFinite(x) && !isFinite(y)) { const a = x > 0 ? roundScaled(PI4, -Number(P)) : roundScaled(3n * PI4, -Number(P)); return y > 0 ? a : -a; }
    if (!isFinite(y)) return y > 0 ? pi2 : -pi2;
    return x > 0 ? (y < 0 || Object.is(y, -0) ? -0 : 0) : (y < 0 || Object.is(y, -0) ? -piCR : piCR);
  }
  const yneg = y < 0 || Object.is(y, -0);
  if (x === 0 && y === 0) return (1 / x > 0) ? y : (yneg ? -piCR : piCR);
  if (y === 0) return (1 / x > 0) ? (yneg ? -0 : 0) : (yneg ? -piCR : piCR);
  if (x === 0) return yneg ? -pi2 : pi2;
  let R = atanFxSigned((toBig(y) << P) / toBig(x));
  if (x < 0) R = (y >= 0) ? R + PI : R - PI;
  return roundScaled(R, -Number(P));
}
