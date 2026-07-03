const B64_CHARS: string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B64URL_CHARS: string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

function base64Encode(data: string, chars: string, pad: boolean): string {
    let result: string = "";
    let i: i32 = 0;
    const dlen: i32 = data.length;
    while (i < dlen) {
        const b0: i32 = data.charCodeAt(i);
        i = i + 1;
        const b1: i32 = i < dlen ? data.charCodeAt(i) : 0;
        if (i < dlen) i = i + 1;
        const b2: i32 = i < dlen ? data.charCodeAt(i) : 0;
        if (i < dlen) i = i + 1;
        result += chars.charAt((b0 >> 2) & 63);
        result += chars.charAt(((b0 & 3) << 4) | ((b1 >> 4) & 15));
        result += chars.charAt(((b1 & 15) << 2) | ((b2 >> 6) & 3));
        result += chars.charAt(b2 & 63);
    }
    const rem: i32 = dlen % 3;
    if (pad) {
        if (rem === 1) {
            const s1: string = result.slice(0, result.length - 2);
            result = s1 + "==";
        } else if (rem === 2) {
            const s2: string = result.slice(0, result.length - 1);
            result = s2 + "=";
        }
    } else {
        if (rem === 1) result = result.slice(0, result.length - 2);
        else if (rem === 2) result = result.slice(0, result.length - 1);
    }
    return result;
}

function base64Decode(encoded: string, chars: string): string {
    const lookup: i32[] = [];
    let j: i32 = 0;
    while (j < 256) {
        lookup.push(-1);
        j = j + 1;
    }
    let k: i32 = 0;
    while (k < chars.length) {
        const code: i32 = chars.charCodeAt(k);
        lookup[code] = k;
        k = k + 1;
    }
    let result: string = "";
    let i: i32 = 0;
    const cleaned: string = encoded.replaceAll("=", "");
    const clen: i32 = cleaned.length;
    while (i < clen) {
        const ch0: i32 = cleaned.charCodeAt(i);
        i = i + 1;
        const lv0: i32 = lookup[ch0];
        const c0: i32 = lv0 < 0 ? 0 : lv0;

        const ch1: i32 = i < clen ? cleaned.charCodeAt(i) : 0;
        if (i < clen) i = i + 1;
        const lv1: i32 = lookup[ch1];
        const c1: i32 = lv1 < 0 ? 0 : lv1;

        const ch2: i32 = i < clen ? cleaned.charCodeAt(i) : 0;
        if (i < clen) i = i + 1;
        const lv2: i32 = lookup[ch2];
        const c2: i32 = lv2 < 0 ? 0 : lv2;

        const ch3: i32 = i < clen ? cleaned.charCodeAt(i) : 0;
        if (i < clen) i = i + 1;
        const lv3: i32 = lookup[ch3];
        const c3: i32 = lv3 < 0 ? 0 : lv3;

        result += String.fromCharCode(((c0 << 2) | (c1 >> 4)) & 255);
        if (i > 2) result += String.fromCharCode(((c1 << 4) | (c2 >> 2)) & 255);
        if (i > 3) result += String.fromCharCode(((c2 << 6) | c3) & 255);
    }
    return result;
}

const data: string = "abc123!?$*&()'-=@~";

const sEnc: string = base64Encode(data, B64_CHARS, true);
console.log(sEnc);
console.log(base64Decode(sEnc, B64_CHARS));
console.log();

const uEnc: string = base64Encode(data, B64URL_CHARS, false);
console.log(uEnc);
console.log(base64Decode(uEnc, B64URL_CHARS));
