// Reference implementation of Margin's end-to-end encryption (docs/SYNC.md).
// The apps (Dart on Android/Windows, later Swift on iPhone) must produce the
// same bytes; the test vectors in test.mjs and in the Flutter tests check that.
import { webcrypto as crypto } from "node:crypto";

export const PBKDF2_ITERATIONS = 310_000;
export const SALT = "margin-sync-v1";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

async function hmac(keyBytes, message) {
  const key = await crypto.subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, message));
}

/// HKDF-SHA256 with an empty salt and one output block (32 bytes).
async function expand(master, info) {
  const prk = await hmac(new Uint8Array(32), master);
  return hmac(prk, new Uint8Array([...encoder.encode(info), 1]));
}

/// Passphrase → { key (32 bytes, AES-256-GCM), vault (64 hex chars, the server token) }.
export async function deriveKeys(passphrase) {
  const base = await crypto.subtle.importKey("raw", encoder.encode(passphrase.trim()), "PBKDF2", false, ["deriveBits"]);
  const master = new Uint8Array(await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt: encoder.encode(SALT), iterations: PBKDF2_ITERATIONS },
    base,
    256,
  ));
  const key = await expand(master, "margin-sync-v1 key");
  const vault = Buffer.from(await expand(master, "margin-sync-v1 vault")).toString("hex");
  return { key, vault };
}

const aad = (uid, updatedAt) => encoder.encode(`${uid}|${updatedAt}`);

/// { type, deleted, data } → blob (base64 of nonce ‖ ciphertext ‖ tag).
export async function seal(keyBytes, uid, updatedAt, payload, nonce = crypto.getRandomValues(new Uint8Array(12))) {
  const key = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["encrypt"]);
  const plain = encoder.encode(JSON.stringify({ v: 1, ...payload }));
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce, additionalData: aad(uid, updatedAt) }, key, plain));
  return Buffer.concat([Buffer.from(nonce), Buffer.from(sealed)]).toString("base64");
}

/// blob → { v, type, deleted, data }. Throws if the key is wrong or anything was changed.
export async function open(keyBytes, uid, updatedAt, blob) {
  const key = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["decrypt"]);
  const bytes = Buffer.from(blob, "base64");
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: bytes.subarray(0, 12), additionalData: aad(uid, updatedAt) },
    key,
    bytes.subarray(12),
  );
  return JSON.parse(decoder.decode(plain));
}
