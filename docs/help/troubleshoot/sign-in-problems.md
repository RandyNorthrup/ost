---
title: Fix sign-in problems
description: When OST asks you to sign in again.
---

# Fix sign-in problems

- If OST shows Microsoft's sign-in page again, sign in as in **Sign in to OST**.
- OST keeps its sign-in in your system's keyring. Make sure a keyring
  service (such as GNOME Keyring or KWallet) is running and unlocked.
  Without one, OST keeps you signed in only until it quits, and
  **Settings ▸ Accounts and orgs** says so. There you can turn on **Stay
  signed in without a keyring** to keep the sign-in in a file only you can
  read instead; a keyring protects it better, and OST moves your sign-in
  there once one works.
- Signing out clears OST's web data too, so OST restarts and the next
  sign-in starts fresh: pick your account again.
- If your organisation requires a compliant device or blocks
  third-party clients, ask your IT admin.
