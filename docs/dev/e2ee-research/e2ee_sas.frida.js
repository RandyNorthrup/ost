// Frida hook to finish Teams' E2EE verification-number derivation.
//
// What it proves, in ONE end-to-end-encrypted 1:1 call:
//  * the inputs and output of the concrete security-code hash in
//    RtmMediaManager.dll (CMediaCallImpl::GetDtlsFingerprintHash ->
//    HashSortedFingerprints, security_code_utils.cpp), and
//  * every SHA-512 / PBKDF2 the call makes (via bcrypt), which confirms
//    SHA-512(sorted fingerprints) -> PBKDF2-HMAC-SHA512(digest, "", 16384, 64).
// Compare the logged `result=...` (64 bytes) with the digits the encryption
// popup shows for the same call to pin down the byte -> 5x4-digit formatting,
// and with OST's logged `security_code_hash` to verify OST's crypto.
//
// Run on winpc (when its GUI is free), while an E2EE call is up:
//   frida -n ms-teams.exe -l e2ee_sas.js
// If several ms-teams.exe processes exist, attach to the one that has
// RtmMediaManager.dll loaded (the call/media process):
//   frida-ps -ai        # find pids
//   for each: frida -p <pid> -l e2ee_sas.js   (it exits quietly if the
//   module is absent). Then open the call's shield -> encryption popup.

'use strict';

// CMediaCallImpl::GetDtlsFingerprintHash combiner (FUN_180068cc0), from the
// Ghidra analysis: void f(out_vec* rcx, span* fpA /*{ptr,len}*/, span* fpB).
const MOD = 'RtmMediaManager.dll';
const COMBINER_RVA = 0x68cc0;

function hex(ptr, n) {
  if (ptr.isNull() || n <= 0 || n > 4096) return '';
  return Array.from(new Uint8Array(ptr.readByteArray(n)))
    .map(b => ('0' + b.toString(16)).slice(-2)).join('');
}

// Read a std::span / {ptr,len} or {len,ptr} 16-byte struct and return bytes.
function readSpan(p) {
  const a = p.readPointer();
  const b = p.add(8).readPointer();
  // One of (a,b) is a small length (<=64), the other a code/heap pointer.
  const av = a.toUInt32(), bv = b.toUInt32();
  if (a.compare(ptr(0x1000)) < 0) return hex(b, av);      // {len, ptr}
  if (b.compare(ptr(0x1000)) < 0) return hex(a, bv);      // {ptr, len}
  return hex(a, 32);                                       // fallback: 32 bytes at a
}

let inHash = 0;

function hookCombiner() {
  const m = Process.findModuleByName(MOD);
  if (!m) return false;
  const fn = m.base.add(COMBINER_RVA);
  console.log('[+] hooking GetDtlsFingerprintHash combiner at ' + fn);
  Interceptor.attach(fn, {
    onEnter(args) {
      inHash++;
      this.out = args[0];
      console.log('[combiner] fpA=' + readSpan(args[1]) + ' fpB=' + readSpan(args[2]));
    },
    onLeave() {
      inHash--;
      // out = Result/expected<vector<u8>>: {okbyte, vec{begin,end,cap}} at a
      // few possible offsets.
      for (const off of [8, 0, 16]) {
        try {
          const beg = this.out.add(off).readPointer();
          const end = this.out.add(off + 8).readPointer();
          const n = end.sub(beg).toInt32();
          if (n > 0 && n <= 128) { console.log('[combiner] result(' + n + ')=' + hex(beg, n)); return; }
        } catch (e) {}
      }
    }
  });
  return true;
}

// bcrypt: log the SHA-512 inputs and the PBKDF2 while the hash runs.
function hookBcrypt() {
  const b = Process.findModuleByName('bcrypt.dll');
  if (!b) return;
  const algOf = new Map(), hashAlg = new Map();
  try {
    Interceptor.attach(b.getExportByName('BCryptOpenAlgorithmProvider'), {
      onEnter(a) { this.ph = a[0]; this.alg = a[1].readUtf16String(); },
      onLeave(r) { if (r.toInt32() === 0) algOf.set(this.ph.readPointer().toString(), this.alg); }
    });
    Interceptor.attach(b.getExportByName('BCryptCreateHash'), {
      onEnter(a) { this.alg = algOf.get(a[0].toString()) || '?'; this.ph = a[1]; },
      onLeave(r) { if (r.toInt32() === 0) hashAlg.set(this.ph.readPointer().toString(), this.alg); }
    });
    Interceptor.attach(b.getExportByName('BCryptHashData'), {
      onEnter(a) {
        const alg = hashAlg.get(a[0].toString()) || '?';
        console.log('[bcrypt ' + alg + '] data(' + a[2].toInt32() + ')=' + hex(a[1], a[2].toInt32()));
      }
    });
    Interceptor.attach(b.getExportByName('BCryptFinishHash'), {
      onEnter(a) { this.out = a[1]; this.n = a[2].toInt32(); this.alg = hashAlg.get(a[0].toString()) || '?'; },
      onLeave() { console.log('[bcrypt ' + this.alg + '] digest=' + hex(this.out, this.n)); }
    });
    const dk = b.findExportByName('BCryptDeriveKeyPBKDF2');
    if (dk) Interceptor.attach(dk, {
      onEnter(a) {
        this.out = a[6]; this.n = a[7].toInt32();
        console.log('[PBKDF2] pw(' + a[2].toInt32() + ')=' + hex(a[1], a[2].toInt32()) +
          ' salt(' + a[4].toInt32() + ')=' + hex(a[3], a[4].toInt32()) +
          ' iters=' + a[5].toInt32() + ' dkLen=' + this.n);
      },
      onLeave() { console.log('[PBKDF2] out=' + hex(this.out, this.n)); }
    });
  } catch (e) { console.log('bcrypt hook error: ' + e); }
}

hookBcrypt();
if (!hookCombiner()) {
  // Wait for the media module to load.
  const ll = Process.getModuleByName('kernelbase.dll').getExportByName('LoadLibraryExW');
  Interceptor.attach(ll, {
    onEnter(a) { this.n = a[0].isNull() ? '' : a[0].readUtf16String(); },
    onLeave() { if (this.n && this.n.toLowerCase().indexOf('rtmmediamanager') >= 0) hookCombiner(); }
  });
}
console.log('[*] e2ee_sas.js ready; open the call\'s encryption popup to trigger the hash');
