Finishing Teams' E2EE verification numbers (TASK-0146 AC3)

Crypto (recovered statically from RtmMediaManager.dll,
MSRTC/.../security_code_utils.cpp, CMediaCallImpl::GetDtlsFingerprintHash):
  fp = each endpoint's 32-byte raw DTLS fingerprint (SHA-256 of its DER cert)
  digest = SHA-512( sorted(fp_low, fp_high) )          # 64 bytes
  hash   = PBKDF2-HMAC-SHA512(digest, salt="", iters=16384, dkLen=64)
OST computes `hash` in src/calling/e2ee.rs::security_code_hash and logs it
("e2ee security code hash") on every E2EE call.

Still unknown: the byte->5x4-digit formatting (in a Teams web chunk not in the
downloaded bundles; not reproducible by brute force over the two captured
calls). To finish, on winpc when its GUI is free:
  1. Start an E2EE 1:1 call (OST <-> Teams, both E2EE switches on).
  2. Attach Frida: `frida -n ms-teams.exe -l e2ee_sas.js` (or by pid to the
     process with RtmMediaManager.dll). Open the shield -> encryption popup.
  3. Record: the popup's five 4-digit groups AND the hook's `result=<64 bytes>`
     / `[PBKDF2] out=`.
  4. Derive the formatting (digits <- result bytes) and confirm `result`
     equals OST's logged `security_code_hash`.
  5. Implement the formatting in e2ee.rs and show the numbers in the encryption
     card; restore both E2EE switches to off afterwards.
Install Frida on winpc: `py -m pip install frida-tools` (authorized).
