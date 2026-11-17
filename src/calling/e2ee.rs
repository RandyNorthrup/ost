//! End-to-end encryption helpers for 1:1 calls.
//!
//! The verification numbers Teams shows under the encryption shield are a
//! "security code" its media engine computes from the two calls' DTLS
//! certificate fingerprints. The derivation was recovered from Teams'
//! `RtmMediaManager.dll` (`MSRTC/src/mediamgr/src/security_code_utils.cpp`,
//! `CMediaCallImpl::GetDtlsFingerprintHash` → `HashSortedFingerprints`),
//! read 2026-11-17:
//!
//! 1. Take each endpoint's raw DTLS fingerprint: the 32-byte SHA-256 of its
//!    DER certificate (the bytes behind the SDP `a=fingerprint:sha-256`).
//! 2. Sort the two fingerprints by byte value (so both sides agree without
//!    knowing who is caller) and concatenate them.
//! 3. `digest = SHA-512(sorted_fp_low || sorted_fp_high)` (64 bytes).
//! 4. `hash = PBKDF2-HMAC-SHA-512(password = digest, salt = "" (empty),
//!    iterations = 16384, dkLen = 64)`.
//!
//! Teams' web UI then renders five 4-digit groups from `hash`. That final
//! byte-to-digits formatting lives in a Teams web chunk that is not in the
//! calling bundle and was not reproducible by brute force over two captured
//! calls, so OST computes the `hash` but does not yet display the digits;
//! [`security_code_hash`] is the verified part, and the formatting is to be
//! confirmed from one live capture (see `scratchpad/frida/e2ee_sas.js` in the
//! task notes) before any numbers are shown.

/// PBKDF2 iterations Teams uses for the security code.
const SECURITY_CODE_ITERATIONS: u32 = 16_384;
/// Derived-key length (bytes).
const SECURITY_CODE_LEN: usize = 64;

/// Teams' DTLS security-code hash for a 1:1 call, from the two endpoints'
/// raw 32-byte DTLS fingerprints (SHA-256 of each DER certificate). The
/// order of the arguments does not matter: the fingerprints are sorted
/// first, so both sides compute the same value.
pub fn security_code_hash(fingerprint_a: &[u8; 32], fingerprint_b: &[u8; 32]) -> [u8; SECURITY_CODE_LEN] {
    let (low, high) = if fingerprint_a <= fingerprint_b {
        (fingerprint_a, fingerprint_b)
    } else {
        (fingerprint_b, fingerprint_a)
    };
    let mut sorted = [0u8; 64];
    sorted[..32].copy_from_slice(low);
    sorted[32..].copy_from_slice(high);
    let digest = openssl::sha::sha512(&sorted);

    let mut out = [0u8; SECURITY_CODE_LEN];
    openssl::pkcs5::pbkdf2_hmac(
        &digest,
        b"",
        SECURITY_CODE_ITERATIONS as usize,
        openssl::hash::MessageDigest::sha512(),
        &mut out,
    )
    .expect("PBKDF2-HMAC-SHA512 with a 64-byte output never fails");
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fp(byte: u8) -> [u8; 32] {
        [byte; 32]
    }

    #[test]
    fn security_code_is_order_independent() {
        let a = fp(0x11);
        let b = fp(0x22);
        assert_eq!(security_code_hash(&a, &b), security_code_hash(&b, &a));
    }

    #[test]
    fn security_code_matches_the_reference_derivation() {
        // Independently recompute SHA-512(sorted) then PBKDF2-HMAC-SHA512.
        let a = fp(0xAA);
        let b = fp(0x55); // sorts before a
        let mut sorted = [0u8; 64];
        sorted[..32].copy_from_slice(&fp(0x55)); // low
        sorted[32..].copy_from_slice(&fp(0xAA)); // high
        let digest = openssl::sha::sha512(&sorted);
        let mut want = [0u8; 64];
        openssl::pkcs5::pbkdf2_hmac(&digest, b"", 16_384, openssl::hash::MessageDigest::sha512(), &mut want).unwrap();
        assert_eq!(security_code_hash(&a, &b), want);
        // Different inputs differ.
        assert_ne!(security_code_hash(&a, &b), security_code_hash(&fp(0x01), &fp(0x02)));
    }
}
