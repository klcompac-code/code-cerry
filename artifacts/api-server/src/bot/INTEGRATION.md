# Bot Integration Architecture

Semua logic berjalan di satu TypeScript runtime (Opsi A).
`senvielle.py` dan `sennv.lua` tidak lagi dipakai — tidak ada proses Python atau Lua eksternal.

## File Struktur

```
src/bot/
├── handler.ts          ← Entry point semua command + rate limiting + helpers
├── anti-vuln.ts        ← Blokir os.* dan io.* (selalu aktif)
├── config.ts           ← Konfigurasi bot
├── db.ts               ← In-memory user store + token restore
├── index.ts            ← Discord client startup
└── commands/
    ├── lua.ts          ← .l  — Luau → Lua 5.3 converter
    ├── obf.ts          ← .obf — Obfuscator
    ├── detect.ts       ← .detect — Deteksi obfuscator
    ├── help.ts
    ├── info.ts
    ├── gift.ts
    ├── blacklist.ts
    ├── setrole.ts
    ├── settoken.ts
    ├── configcmd.ts
    └── setconfig.ts
```

## Anti-Vuln

Semua command yang menerima Lua code (`.l`, `.obf`) memanggil `checkAntiVuln()` dari `anti-vuln.ts`.

Library yang **diblokir**: `os` dan `io` (seluruh method-nya).

Library yang **TIDAK diblokir** (diizinkan): `load`, `loadstring`, `require`, `pcall`, `xpcall`,
`game`, `workspace`, `script`, dan seluruh Roblox/Luau API lainnya.

Anti-vuln **selalu aktif** — tidak ada toggle config untuk menonaktifkannya.
