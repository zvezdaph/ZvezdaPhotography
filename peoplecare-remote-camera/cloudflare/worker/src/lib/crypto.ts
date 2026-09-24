import { PAIRING_ALPHABET, PAIRING_CODE_LENGTH } from "../shared/protocol";

const encoder = new TextEncoder();

export function randomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

export function toHex(bytes: Uint8Array): string {
  let out = "";
  for (const b of bytes) out += b.toString(16).padStart(2, "0");
  return out;
}

export function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** URL-safe random secret, 256 bit by default. */
export function randomToken(byteLength = 32): string {
  return toBase64Url(randomBytes(byteLength));
}

export function randomId(prefix: string, byteLength = 8): string {
  return `${prefix}_${toHex(randomBytes(byteLength))}`;
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return toHex(new Uint8Array(digest));
}

/**
 * Constant time comparison of two secrets. Both values are hashed first so the
 * comparison does not leak their length.
 */
export async function secretsEqual(a: string, b: string): Promise<boolean> {
  const [da, db] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(a)),
    crypto.subtle.digest("SHA-256", encoder.encode(b)),
  ]);
  const subtle = crypto.subtle as SubtleCrypto & {
    timingSafeEqual?: (x: ArrayBuffer | ArrayBufferView, y: ArrayBuffer | ArrayBufferView) => boolean;
  };
  if (typeof subtle.timingSafeEqual === "function") {
    return subtle.timingSafeEqual(da, db);
  }
  const x = new Uint8Array(da);
  const y = new Uint8Array(db);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

/**
 * 8 symbol code from a 32 symbol alphabet (40 bit). 256 is a multiple of 32,
 * so `byte % 32` is not biased.
 */
export function generatePairingCode(): string {
  const bytes = randomBytes(PAIRING_CODE_LENGTH);
  let code = "";
  for (const b of bytes) code += PAIRING_ALPHABET[b % PAIRING_ALPHABET.length];
  return code;
}
