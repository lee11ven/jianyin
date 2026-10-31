/**
 * Simple in-memory OTP store. Each entry expires after ttlMs.
 * Used only for register/login OTP — never persisted to disk.
 */
const store = new Map();
const DEFAULT_TTL_MS = 60_000; // 60 s
const DEFAULT_CODE_LEN = 6;

/**
 * Generate a numeric OTP code.
 */
export function generateOtpCode(length = DEFAULT_CODE_LEN) {
  const n = Math.floor(Math.random() * 10 ** length);
  return String(n).padStart(length, '0');
}

/**
 * Store an OTP for [phone] with TTL. Returns the code (for local display in debug).
 */
export function storeOtp(phone, ttlMs = DEFAULT_TTL_MS) {
  const code = generateOtpCode();
  const expiresAt = Date.now() + ttlMs;
  store.set(phone, { code, expiresAt });
  return code;
}

/**
 * Verify [phone] OTP. Returns true if valid, clears the entry on success.
 */
export function verifyOtp(phone, code) {
  const entry = store.get(phone);
  if (!entry) return false;
  if (Date.now() > entry.expiresAt) {
    store.delete(phone);
    return false;
  }
  const match = code === entry.code;
  if (match) store.delete(phone);
  return match;
}

/**
 * Remaining ms until expiry, or 0 if not found / expired.
 */
export function otpRemainingMs(phone) {
  const entry = store.get(phone);
  if (!entry) return 0;
  const remaining = entry.expiresAt - Date.now();
  if (remaining <= 0) {
    store.delete(phone);
    return 0;
  }
  return remaining;
}

/**
 * Clear all entries (call on server shutdown).
 */
export function clearOtps() {
  store.clear();
}
