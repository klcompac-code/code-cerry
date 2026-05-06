# Setup Bot di PC Lokal

## 1. Install Node.js
Pastikan Node.js v18+ sudah terinstall: https://nodejs.org

## 2. Install dependencies
```bash
npm install
```

## 3. Buat file .env
Copy `.env.example` → `.env` lalu isi nilai yang diperlukan:
```bash
cp .env.example .env
```
Edit `.env` dan isi minimal:
- `DISCORD_BOT_TOKEN` — token bot dari Discord Developer Portal
- `BOT_OWNER_IDS` — Discord User ID kamu
- `PORT=3000`
- `NODE_ENV=production`
- `BOT_ENABLED=true`

## 4. Install Lua (untuk command .l dan .obf)
- **Windows**: https://luabinaries.sourceforge.net/ (download lua-5.3 atau lua-5.4)
- **Linux**: `sudo apt install lua5.3`
- **Mac**: `brew install lua`

Setelah install Lua, set di `.env`:
```
PROMETHEUS_PATH=./src/bot/Prometheus/prometheus-main.lua
```

## 5. Jalankan bot
```bash
npm start
```

## Catatan
- Jika ada error `Cannot find module`, pastikan sudah menjalankan `npm install`
- File `.env` **jangan** di-share atau di-upload ke GitHub
