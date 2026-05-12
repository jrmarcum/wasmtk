const B64_CHARS: string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B64URL_CHARS: string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

function base64Encode(data: string, chars: string, pad: boolean): string {
    let result: string = "";
    let i: number = 0;
    while (i < data.length) {
        const b0: number = data.charCodeAt(i++);
        const b1: number = i < data.length ? data.charCodeAt(i++) : 0;
        const b2: number = i < data.length ? data.charCodeAt(i++) : 0;
        result += chars[(b0 >> 2) & 63];
        result += chars[((b0 & 3) << 4) | ((b1 >> 4) & 15)];
        result += chars[((b1 & 15) << 2) | ((b2 >> 6) & 3)];
        result += chars[b2 & 63];
    }
    if (pad) {
        const rem: number = data.length % 3;
        if (rem === 1) result = result.slice(0, result.length - 2) + "==";
        else if (rem === 2) result = result.slice(0, result.length - 1) + "=";
    } else {
        const rem: number = data.length % 3;
        if (rem === 1) result = result.slice(0, result.length - 2);
        else if (rem === 2) result = result.slice(0, result.length - 1);
    }
    return result;
}

function base64Decode(encoded: string, chars: string): string {
    const lookup: number[] = [];
    for (let i: number = 0; i < 256; i++) lookup.push(-1);
    for (let i: number = 0; i < chars.length; i++) lookup[chars.charCodeAt(i)] = i;
    let result: string = "";
    let i: number = 0;
    const cleaned: string = encoded.replace(/=/g, "");
    while (i < cleaned.length) {
        const c0: number = lookup[cleaned.charCodeAt(i++)] ?? 0;
        const c1: number = i < cleaned.length ? (lookup[cleaned.charCodeAt(i++)] ?? 0) : 0;
        const c2: number = i < cleaned.length ? (lookup[cleaned.charCodeAt(i++)] ?? 0) : 0;
        const c3: number = i < cleaned.length ? (lookup[cleaned.charCodeAt(i++)] ?? 0) : 0;
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
