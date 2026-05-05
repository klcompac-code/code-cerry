# Bot Integration Module

Modul ini mengintegrasikan logika dari `senvielle.py` dan `sennv.lua` ke dalam server API Discord Bot.

## File-File yang Terintegrasi

### 1. **senvielle.py** 
- File Python asli dari parent folder
- Berisi: Discord bot commands, Lua deobfuscation logic, rate limiting
- Teradaptasi ke TypeScript dalam `python-integration.ts`

### 2. **sennv.lua**
- File Lua asli dari parent folder  
- Berisi: Lua dumper, object serialization, code beautification
- Teradaptasi ke TypeScript dalam `lua-integration.ts`

## File Adapter yang Dibuat

### `python-integration.ts`
Mengimplementasikan logika dari `senvielle.py`:
- ✅ Rate limiting per user
- ✅ Lua code processing (strip comments, rename variables, beautify, fix syntax)
- ✅ Code extraction dari berbagai sumber (codeblock, file, reply)
- ✅ Discord message formatting dengan limit handling
- ✅ URL validation untuk SSRF protection

**Fungsi Utama:**
```typescript
checkRateLimit(userId: string): number
processLuaCode(code: string, options: CommandOptions): Promise<string>
extractCodeFromMessage(msg: Message): Promise<string | null>
sendFormattedResponse(msg: Message, content: string): Promise<void>
isValidUrl(url: string): boolean
```

### `lua-integration.ts`
Mengimplementasikan logika dari `sennv.lua`:
- ✅ Lua dump execution
- ✅ Lua beautification
- ✅ Code formatting dan output handling
- ✅ Integration dengan Discord messages

**Fungsi Utama:**
```typescript
executeLuaDump(code: string): Promise<string>
executeLuaBeautify(code: string): Promise<string>
processLuaMessage(msg: Message, code: string): Promise<void>
```

## Integrasi dengan Handler

File `handler.ts` telah diupdate untuk menggunakan kedua adapter:

1. **Rate Limiting** - Setiap user token-command dikenakan cooldown
2. **Code Processing** - Menggunakan `processLuaCode()` untuk berbagai transformasi
3. **Message Extraction** - Menggunakan `extractCodeFromMessage()` untuk mengambil code
4. **Response Formatting** - Menggunakan `sendFormattedResponse()` untuk output

## Lokasi File

```
src/
├── bot/
│   ├── python-integration.ts    (Adapter Python)
│   ├── lua-integration.ts       (Adapter Lua)
│   ├── senvielle.py            (Original Python file)
│   ├── sennv.lua               (Original Lua file)
│   ├── handler.ts              (Updated with integrations)
│   ├── commands/
│   ├── config.ts
│   ├── db.ts
│   └── index.ts
└── ...
```

## Cara Menggunakan

### Dari Command Handler
```typescript
// Contoh penggunaan di command
const code = await extractCodeFromMessage(msg);
const processed = await processLuaCode(code, {
  stripComments: true,
  renameVariables: true,
  beautify: true
});
await sendFormattedResponse(msg, processed);
```

### Rate Limiting
```typescript
const cooldown = checkRateLimit(msg.author.id);
if (cooldown > 0) {
  // Masih dalam cooldown period
}
```

### Lua Operations
```typescript
const dumped = await executeLuaDump(code);
const beautified = await executeLuaBeautify(dumped);
```

## Environment Variables

Pastikan `.env` memiliki:
```env
DISCORD_BOT_TOKEN=your_token_here
NODE_ENV=production
BOT_ENABLED=true
```

## Catatan

- Kedua file original (`senvielle.py` dan `sennv.lua`) disimpan di folder bot untuk referensi
- Adapter TypeScript melakukan wrapping dan adaptasi logika untuk kompatibilitas
- Rate limiting default: 5 detik antar command per user
- Lua code beautification menggunakan indentation 2 spaces
- URL validation mencegah SSRF attacks dengan memblokir local/internal addresses
