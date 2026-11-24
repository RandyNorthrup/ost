//! End-to-end encryption helpers for 1:1 calls.
//!
//! The verification numbers Teams shows under the encryption shield are a
//! "security code" its media engine computes from the two endpoints' DTLS
//! certificate fingerprints, then its web UI formats. Both halves were
//! recovered from Teams (2026-11-17):
//!
//! Native (`RtmMediaManager.dll`, `MSRTC/src/mediamgr/src/
//! security_code_utils.cpp`, `CMediaCallImpl::GetDtlsFingerprintHash`):
//! 1. Each endpoint's raw DTLS fingerprint: the 32-byte SHA-256 of its DER
//!    certificate (the bytes behind the SDP `a=fingerprint:sha-256`).
//! 2. Sort the two by byte value (both sides agree without knowing who is
//!    caller) and `digest = SHA-512(low || high)` (`HashSortedFingerprints`).
//! 3. `key = PBKDF2-HMAC-SHA-512(password = digest, salt = "", iterations =
//!    16384, dkLen = 64)` (`spl::pbkdf2Hmac` → `BCryptDeriveKeyPBKDF2`).
//! 4. `GetDtlsFingerprintHash` returns the **last 16 bytes** of `key`.
//!
//! Web UI (the e2ee status popup's `fingerprintHash` formatter, from Teams'
//! cached chunk): hex-encode the 16 bytes, split into 8-hex-digit chunks,
//! `parseInt(chunk, 16) % 100000` zero-padded to 5 digits, join (20 digits),
//! and split into groups of 4: five 4-digit numbers.
//!
//! Checked against two live calls with Teams desktop (see the tests).

/// PBKDF2 iterations Teams uses for the security code.
const SECURITY_CODE_ITERATIONS: usize = 16_384;
/// Derived-key length (bytes).
const SECURITY_CODE_LEN: usize = 64;
/// How many bytes of the derived key `GetDtlsFingerprintHash` returns (the
/// last ones).
const FINGERPRINT_HASH_LEN: usize = 16;

/// Teams' DTLS fingerprint hash for a 1:1 call (`GetDtlsFingerprintHash`),
/// from the two endpoints' raw 32-byte DTLS fingerprints (SHA-256 of each
/// DER certificate). Argument order does not matter.
pub fn fingerprint_hash(fingerprint_a: &[u8; 32], fingerprint_b: &[u8; 32]) -> [u8; FINGERPRINT_HASH_LEN] {
    let (low, high) = if fingerprint_a <= fingerprint_b {
        (fingerprint_a, fingerprint_b)
    } else {
        (fingerprint_b, fingerprint_a)
    };
    let mut sorted = [0u8; 64];
    sorted[..32].copy_from_slice(low);
    sorted[32..].copy_from_slice(high);
    let digest = openssl::sha::sha512(&sorted);

    let mut key = [0u8; SECURITY_CODE_LEN];
    openssl::pkcs5::pbkdf2_hmac(
        &digest,
        b"",
        SECURITY_CODE_ITERATIONS,
        openssl::hash::MessageDigest::sha512(),
        &mut key,
    )
    .expect("PBKDF2-HMAC-SHA512 with a 64-byte output never fails");
    let mut out = [0u8; FINGERPRINT_HASH_LEN];
    out.copy_from_slice(&key[SECURITY_CODE_LEN - FINGERPRINT_HASH_LEN..]);
    out
}

/// Teams' popup formatting of a fingerprint hash: 8-hex-digit chunks, each
/// `% 100000` zero-padded to 5 digits, joined and split into 4-digit groups.
pub fn format_numbers(hash: &[u8]) -> Vec<String> {
    let hex: String = hash.iter().map(|b| format!("{b:02x}")).collect();
    let digits: String = hex
        .as_bytes()
        .chunks(8)
        .map(|c| {
            let v = u64::from_str_radix(std::str::from_utf8(c).unwrap_or("0"), 16).unwrap_or(0);
            format!("{:05}", v % 100_000)
        })
        .collect();
    digits
        .as_bytes()
        .chunks(4)
        .map(|c| String::from_utf8_lossy(c).into_owned())
        .collect()
}

/// The five 4-digit verification numbers Teams shows for a 1:1 end-to-end
/// encrypted call between endpoints with these DTLS fingerprints.
pub fn security_numbers(fingerprint_a: &[u8; 32], fingerprint_b: &[u8; 32]) -> Vec<String> {
    format_numbers(&fingerprint_hash(fingerprint_a, fingerprint_b))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fp(s: &str) -> [u8; 32] {
        let v: Vec<u8> = s.split(':').map(|h| u8::from_str_radix(h, 16).unwrap()).collect();
        v.try_into().unwrap()
    }

    #[test]
    fn numbers_match_teams_on_two_live_calls() {
        // Teams desktop (winpc) calling OST Test 2 with E2EE on, 2026-11-17:
        // the SDP offer's and answer's fingerprints, and the numbers Teams'
        // encryption popup showed.
        let teams = fp("8F:DF:43:E3:C8:6F:63:9B:E1:12:15:52:2B:B3:A6:54:6A:4E:DB:EF:6F:BB:C1:58:F1:86:11:A5:AB:E0:5F:7F");
        let ost = fp("76:FA:D8:33:B4:4E:A1:E0:77:96:C4:27:DC:B6:C2:4B:A9:90:ED:5F:B0:70:28:91:03:B0:FF:43:5D:CC:7A:87");
        assert_eq!(security_numbers(&teams, &ost), ["4507", "0411", "8497", "0193", "3733"]);
        let teams = fp("90:5A:DB:4E:6F:C7:8B:32:5E:09:5B:4B:6F:98:1C:E8:8F:40:48:DC:1E:EF:43:0B:4B:EB:64:28:7D:44:AD:7B");
        let ost = fp("7E:9D:8B:58:F9:E7:93:51:83:E6:AB:BD:2F:04:61:46:19:32:4A:61:A7:CA:14:AD:2D:2D:A7:6E:61:B4:37:B2");
        assert_eq!(security_numbers(&teams, &ost), ["6167", "3878", "8004", "3470", "2825"]);
        // Either side computes the same numbers.
        assert_eq!(security_numbers(&ost, &teams), ["6167", "3878", "8004", "3470", "2825"]);
    }

    #[test]
    fn format_is_teams_popup_formatter() {
        // 0xffffffff % 100000 = 67295; four chunks -> 20 digits -> 5 groups.
        assert_eq!(format_numbers(&[0xff; 16]), ["6729", "5672", "9567", "2956", "7295"]);
        assert_eq!(format_numbers(&[0; 16]), ["0000", "0000", "0000", "0000", "0000"]);
    }
}
