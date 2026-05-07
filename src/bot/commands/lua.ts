/**
 * lua.ts  –  Full Lua deobfuscation & utility command handler
 *
 * Logic ported from:
 *   - senvielle.py  (Python bot / processing pipeline)
 *   - sennv.lua     (Lua dumper wrapper / compat layer)
 *
 * Features:
 *   • User tiers: owner → coowner → premium → free
 *   • Owner / CoOwner management commands (.addowner, .removeowner, .addcoowner, .removecoowner)
 *   • .setpremium / .setfree  (owner + coowner only)
 *   • Per-user rate limiting
 *   • Log channel routing (.setlogchannel)
 *   • SSRF-safe URL fetching
 *   • Full Lua/Luau compat-fix pipeline (senvielle.py port)
 *   • Dumper runner wrapper (sennv.lua integration)
 *   • Pastefy upload
 *   • Commands: .l  .bf  .darklua  .get  .help
 *               .setpremium  .setfree  .addcoowner  .removecoowner
 *               .setlogchannel  .info  .bl  .setrole  .settoken
 */

import {
  Message,
  AttachmentBuilder,
  TextChannel,
  EmbedBuilder,
  ActionRowBuilder,
  StringSelectMenuBuilder,
  StringSelectMenuOptionBuilder,
  ButtonBuilder,
  ButtonStyle,
  ComponentType,
  StringSelectMenuInteraction,
  ButtonInteraction,
} from "discord.js";
import { spawn } from "child_process";
import { randomBytes, createCipheriv, createDecipheriv, scryptSync } from "crypto";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import { logger } from "../../lib/logger";

// ─────────────────────────────────────────────────────────────────────────────
// FILE NAME (for log attribution)
// ─────────────────────────────────────────────────────────────────────────────

const FILE_NAME = "lua.ts";

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS  (ported from senvielle.py)
// ─────────────────────────────────────────────────────────────────────────────

const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5 MB
const DUMP_TIMEOUT_MS = 130_000;        // 130 s – must exceed sennv.lua TIMEOUT_SECONDS (120 s)
const RATE_LIMIT_SECONDS = 5;
const DISCORD_RETRY_ATTEMPTS = 3;
const DISCORD_RETRY_DELAY_MS = 2_000;

// Path to the Lua dumper script (sennv.lua must live next to this file at runtime)
const DUMPER_PATH = path.join(__dirname, "..", "sennv.lua");

// Lua interpreters to try, in order (same list as senvielle.py)
const LUA_INTERPRETERS = ["lua5.3", "lua5.1", "lua5.4", "luajit", "lua"];

// Embed colours
const COLOR_OK   = 0x57F287; // green
const COLOR_FAIL = 0xED4245; // red
const COLOR_INFO = 0x5865F2; // blurple
const COLOR_WARN = 0xFEE75C; // yellow

// ─────────────────────────────────────────────────────────────────────────────
// USER TIER SYSTEM
// ─────────────────────────────────────────────────────────────────────────────

export type UserTier = "owner" | "coowner" | "premium" | "free";

interface UserRecord {
  userId: string;
  tier: UserTier;
  blacklisted: boolean;
  blacklistReason: string;
  blacklistExpiry: number | null;
  commandsUsed: number;
  tokens: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// FIX 1: ENKRIPSI AES-256-GCM untuk users.json
// Key diambil dari env DB_ENCRYPTION_KEY (wajib di-set di .env)
// Format file: <16-byte IV hex>:<16-byte authTag hex>:<ciphertext hex>
// ─────────────────────────────────────────────────────────────────────────────

const DB_PATH = path.join(process.cwd(), "data", "users.enc");
const DB_ALGO = "aes-256-gcm";

function getDbKey(): Buffer {
  const rawKey = process.env["DB_ENCRYPTION_KEY"];
  if (!rawKey) {
    logger.warn({ source: FILE_NAME }, "DB_ENCRYPTION_KEY tidak di-set — data tersimpan tapi TIDAK terenkripsi. Set env var ini segera!");
    // Fallback: gunakan key deterministik dari hostname agar tidak crash,
    // tapi tetap beri peringatan keras.
    return scryptSync("fallback-insecure-key-" + os.hostname(), "saltbot", 32);
  }
  // Derive 32-byte key dari passphrase menggunakan scrypt
  return scryptSync(rawKey, "senv-bot-salt-v1", 32);
}

function encryptDb(plaintext: string): string {
  const key = getDbKey();
  const iv  = randomBytes(16);
  const cipher = createCipheriv(DB_ALGO, key, iv);
  const enc = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString("hex")}:${tag.toString("hex")}:${enc.toString("hex")}`;
}

function decryptDb(payload: string): string {
  const parts = payload.split(":");
  if (parts.length !== 3) throw new Error("Invalid encrypted DB format");
  const [ivHex, tagHex, encHex] = parts;
  const key     = getDbKey();
  const iv      = Buffer.from(ivHex, "hex");
  const tag     = Buffer.from(tagHex, "hex");
  const encData = Buffer.from(encHex, "hex");
  const decipher = createDecipheriv(DB_ALGO, key, iv);
  decipher.setAuthTag(tag);
  return decipher.update(encData).toString("utf8") + decipher.final("utf8");
}

// ─────────────────────────────────────────────────────────────────────────────
// FIX 2 (partial): SIGTERM/SIGINT dipindahkan ke index.ts — export persistDb
// ─────────────────────────────────────────────────────────────────────────────

function loadDb(): Map<string, UserRecord> {
  try {
    if (fs.existsSync(DB_PATH)) {
      const payload  = fs.readFileSync(DB_PATH, "utf8").trim();
      const plaintext = decryptDb(payload);
      const raw = JSON.parse(plaintext);
      return new Map(Object.entries(raw) as [string, UserRecord][]);
    }
  } catch (e) {
    logger.warn({ e, source: FILE_NAME }, "Gagal load userDb dari disk, mulai fresh (mungkin key salah atau file corrupt)");
  }
  return new Map();
}

export function persistDb() {
  try {
    const dir = path.dirname(DB_PATH);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const plaintext  = JSON.stringify(Object.fromEntries(userDb));
    const encrypted  = encryptDb(plaintext);
    fs.writeFileSync(DB_PATH, encrypted, "utf8");
  } catch (e) {
    logger.error({ e, source: FILE_NAME }, "Gagal persist userDb");
  }
}

const userDb = loadDb();

// Auto-persist setiap 5 menit (SIGTERM/SIGINT ditangani di index.ts — FIX 2)
setInterval(persistDb, 5 * 60_000);

// Owner IDs come from environment variable (comma-separated)
function getOwnerIds(): string[] {
  return (process.env["BOT_OWNER_IDS"] ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

// In-memory coowner list (owner can add/remove at runtime)
const coOwnerIds = new Set<string>(
  (process.env["BOT_COOWNER_IDS"] ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
);

export function isOwner(userId: string): boolean {
  return getOwnerIds().includes(userId);
}

export function isCoOwner(userId: string): boolean {
  return coOwnerIds.has(userId);
}

export function isOwnerOrCoOwner(userId: string): boolean {
  return isOwner(userId) || isCoOwner(userId);
}

function resolveDefaultTier(userId: string): UserTier {
  if (isOwner(userId)) return "owner";
  if (isCoOwner(userId)) return "coowner";
  return "free";
}

const FREE_DEFAULT_TOKENS    = 50;
const PREMIUM_DEFAULT_TOKENS = 500;
const FREE_MAX_TOKENS        = 100;
const PREMIUM_MAX_TOKENS     = 1000;
const TOKEN_RESTORE_AMOUNT   = 1;
const TOKEN_RESTORE_INTERVAL = 60 * 60 * 1000; // 1 h

export function getUser(userId: string): UserRecord {
  if (!userDb.has(userId)) {
    const tier = resolveDefaultTier(userId);
    userDb.set(userId, {
      userId,
      tier,
      blacklisted: false,
      blacklistReason: "",
      blacklistExpiry: null,
      commandsUsed: 0,
      tokens:
        tier === "owner" || tier === "coowner"
          ? Infinity
          : tier === "premium"
          ? PREMIUM_DEFAULT_TOKENS
          : FREE_DEFAULT_TOKENS,
    });
  }
  const user = userDb.get(userId)!;
  // Always refresh tier for owners / coowners in case env changed
  const freshTier = resolveDefaultTier(userId);
  if ((freshTier === "owner" || freshTier === "coowner") && user.tier !== freshTier) {
    user.tier = freshTier;
    user.tokens = Infinity;
  }
  return user;
}

export function saveUser(record: UserRecord) {
  userDb.set(record.userId, record);
}

export function isBlacklisted(userId: string): boolean {
  if (isOwner(userId)) return false;
  const user = getUser(userId);
  if (!user.blacklisted) return false;
  if (user.blacklistExpiry !== null && Date.now() > user.blacklistExpiry) {
    user.blacklisted = false;
    user.blacklistReason = "";
    user.blacklistExpiry = null;
    saveUser(user);
    return false;
  }
  return true;
}

export function hasTokens(userId: string): boolean {
  const user = getUser(userId);
  if (user.tier === "owner" || user.tier === "coowner") return true;
  return user.tokens > 0;
}

export function deductToken(userId: string) {
  const user = getUser(userId);
  if (user.tier === "owner" || user.tier === "coowner") return;
  user.tokens = Math.max(0, user.tokens - 1);
  saveUser(user);
}

// Start background token restore loop (call once from bot init)
export function startTokenRestore() {
  setInterval(() => {
    for (const user of userDb.values()) {
      if (user.tier === "owner" || user.tier === "coowner") continue;
      const max = user.tier === "premium" ? PREMIUM_MAX_TOKENS : FREE_MAX_TOKENS;
      if (user.tokens < max) {
        user.tokens = Math.min(max, user.tokens + TOKEN_RESTORE_AMOUNT);
        saveUser(user);
      }
    }
  }, TOKEN_RESTORE_INTERVAL);
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGGING CHANNEL
// ─────────────────────────────────────────────────────────────────────────────

let logChannelId: string | null = process.env["BOT_LOG_CHANNEL_ID"] ?? null;
let logChannelGuildId: string | null = null;

export function setLogChannel(channelId: string, guildId?: string) {
  logChannelId = channelId;
  if (guildId) logChannelGuildId = guildId;
}

export function getLogChannelId(): string | null {
  return logChannelId;
}

export function getLogChannelGuildId(): string | null {
  return logChannelGuildId;
}

/**
 * Send a log embed to the configured log channel.
 * Falls back to the pino logger when no channel is configured or the send fails.
 */
// ─────────────────────────────────────────────────────────────────────────────
// FIX #4: SANITIZE ERROR — Hapus path server sebelum dikirim ke log channel
// ─────────────────────────────────────────────────────────────────────────────

function sanitizeErrorForLog(err: string): string {
  return err
    .replace(/\/[a-zA-Z0-9_\-./]+\.(lua|ts|js|py)/g, "<path>")
    .replace(/\/home\/[^/\s]+/g, "<home>")
    .replace(/\/tmp\/[^/\s]+/g, "<tmp>")
    .replace(/\/root\/[^/\s]+/g, "<root>")
    .replace(/\/var\/[^/\s]+/g, "<var>");
}

// ─────────────────────────────────────────────────────────────────────────────
// FIX #8: SEMAPHORE — Batasi concurrent Lua execution (max 3 bersamaan)
// ─────────────────────────────────────────────────────────────────────────────

class Semaphore {
  private count: number;
  private queue: Array<() => void> = [];

  constructor(maxConcurrent: number) {
    this.count = maxConcurrent;
  }

  get atCapacity(): boolean {
    return this.count <= 0;
  }

  async acquire(): Promise<() => void> {
    if (this.count > 0) {
      this.count--;
      return () => this.release();
    }
    return new Promise((resolve) => {
      this.queue.push(() => { this.count--; resolve(() => this.release()); });
    });
  }

  private release() {
    this.count++;
    const next = this.queue.shift();
    if (next) next();
  }
}

const dumpSemaphore = new Semaphore(3); // Maksimal 3 dump bersamaan

async function sendLogEmbed(
  client: Message["client"] | null,
  level: "info" | "warn" | "error",
  title: string,
  description: string,
  extra?: Record<string, string>
) {
  const color = level === "error" ? COLOR_FAIL : level === "warn" ? COLOR_WARN : COLOR_INFO;

  // Always log to pino
  const pinoData = { title, description, extra, source: FILE_NAME };
  if (level === "error") logger.error(pinoData, `[${FILE_NAME}] ${title}`);
  else if (level === "warn")  logger.warn(pinoData,  `[${FILE_NAME}] ${title}`);
  else                        logger.info(pinoData,  `[${FILE_NAME}] ${title}`);

  if (!client || !logChannelId) return;

  try {
    const channel = await client.channels.fetch(logChannelId);
    if (!channel || !channel.isTextBased()) return;

    const embed = new EmbedBuilder()
      .setColor(color)
      .setTitle(`[${FILE_NAME}] ${title}`)
      .setDescription(sanitizeErrorForLog(description))
      .setTimestamp();

    if (extra) {
      for (const [k, v] of Object.entries(extra)) {
        embed.addFields({ name: k, value: v, inline: true });
      }
    }

    await (channel as TextChannel).send({ embeds: [embed] });
  } catch (err) {
    logger.error({ err, source: FILE_NAME }, "Failed to send log embed to log channel");
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RATE LIMITING
// ─────────────────────────────────────────────────────────────────────────────

const userLastUse = new Map<string, number>();

// FIX #6: Rate limit berbeda per command tier
const RATE_LIMITS: Record<string, number> = {
  ".l":       10,  // 10s — paling berat (eksekusi Lua)
  ".bf":       3,  // 3s  — ringan (beautify)
  ".darklua":  5,  // 5s  — medium
  ".get":      2,  // 2s  — hanya download
  ".stats":   15,  // FIX 4: 15s — cegah spam embed stats
};

const commandCooldowns = new Map<string, Map<string, number>>();

function checkRateLimit(userId: string, cmd?: string): number {
  if (isOwner(userId)) return 0;

  // Per-command rate limit jika cmd diberikan
  if (cmd && RATE_LIMITS[cmd] !== undefined) {
    const limit = RATE_LIMITS[cmd];
    if (!commandCooldowns.has(cmd)) commandCooldowns.set(cmd, new Map());
    const bucket = commandCooldowns.get(cmd)!;
    const now = Date.now();
    const last = bucket.get(userId) ?? 0;
    const elapsed = (now - last) / 1000;
    if (elapsed < limit) return limit - elapsed;
    bucket.set(userId, now);
    return 0;
  }

  // Fallback: global rate limit
  const now = Date.now();
  const last = userLastUse.get(userId) ?? 0;
  const elapsed = (now - last) / 1000;
  if (elapsed < RATE_LIMIT_SECONDS) return RATE_LIMIT_SECONDS - elapsed;
  userLastUse.set(userId, now);
  return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// RETRY HELPER
// ─────────────────────────────────────────────────────────────────────────────

// FIX #11: Retry lebih lengkap — handle 429, 500, 502, 503, 504
const RETRYABLE_STATUS = new Set([429, 500, 502, 503, 504]);

async function withRetry<T>(fn: () => Promise<T>, label = ""): Promise<T> {
  for (let attempt = 0; attempt < DISCORD_RETRY_ATTEMPTS; attempt++) {
    try {
      return await fn();
    } catch (err: any) {
      const status = err?.status ?? err?.httpStatus;
      const isRetryable = RETRYABLE_STATUS.has(status);
      const isLast = attempt >= DISCORD_RETRY_ATTEMPTS - 1;

      if (isRetryable && !isLast) {
        const retryAfter = err?.retryAfter ?? (DISCORD_RETRY_DELAY_MS * (attempt + 1));
        logger.warn({ attempt, status, label, source: FILE_NAME }, "Discord retry");
        await sleep(retryAfter);
      } else {
        throw err;
      }
    }
  }
  throw new Error("unreachable");
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

// ─────────────────────────────────────────────────────────────────────────────
// SSRF / URL VALIDATION  (ported from senvielle.py _is_safe_url)
// ─────────────────────────────────────────────────────────────────────────────

const BLOCKED_HOST_RE = /^(localhost|.*\.local|.*\.internal|.*\.intranet)$/i;

function isSafeUrl(url: string): { safe: boolean; reason: string } {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return { safe: false, reason: "invalid URL" };
  }

  if (!["http:", "https:"].includes(parsed.protocol)) {
    return { safe: false, reason: `scheme '${parsed.protocol}' not allowed` };
  }

  const hostname = parsed.hostname;
  if (!hostname) return { safe: false, reason: "no hostname" };
  if (BLOCKED_HOST_RE.test(hostname)) return { safe: false, reason: "internal hostname" };

  // Block private IPv4 ranges
  const PRIVATE_RE = [
    /^127\./,
    /^192\.168\./,
    /^10\./,
    /^172\.(1[6-9]|2\d|3[01])\./,
    /^169\.254\./,
    /^0\./,
  ];
  if (PRIVATE_RE.some((p) => p.test(hostname))) {
    return { safe: false, reason: `IP '${hostname}' is not public` };
  }

  // FIX #3: Blokir IPv6 loopback dan private ranges
  const IPV6_BLOCKED = [
    /^\[?::1\]?$/,            // loopback
    /^\[?fc[0-9a-f]{2}:/i,   // unique local
    /^\[?fd[0-9a-f]{2}:/i,   // unique local
    /^\[?fe80:/i,             // link-local
    /^\[?::ffff:/i,           // IPv4-mapped
    /^\[?::\]?$/,             // unspecified
  ];
  if (IPV6_BLOCKED.some((p) => p.test(hostname))) {
    return { safe: false, reason: `IPv6 address '${hostname}' is not allowed` };
  }

  // FIX #3b: Blokir URL dengan embedded credentials (user:pass@host)
  if (parsed.username || parsed.password) {
    return { safe: false, reason: "URL credentials not allowed" };
  }

  // FIX #3c: Batasi panjang URL
  if (url.length > 2048) {
    return { safe: false, reason: "URL too long (max 2048 chars)" };
  }

  return { safe: true, reason: "" };
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP FETCH  (ported from senvielle.py _requests_get, with browser headers)
// ─────────────────────────────────────────────────────────────────────────────

const BROWSER_HEADERS: HeadersInit = {
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  Accept:
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
  "Accept-Language": "en-US,en;q=0.9",
  "Accept-Encoding": "gzip, deflate, br",
  "Cache-Control": "max-age=0",
};

async function fetchUrl(url: string, timeoutMs = 8_000, asExecutor = false): Promise<Buffer | null> {
  const { safe, reason } = isSafeUrl(url);
  if (!safe) {
    logger.warn({ url, reason, source: FILE_NAME }, "[security] blocked request");
    return null;
  }

  const controller = new AbortController();
  const tid = setTimeout(() => controller.abort(), timeoutMs);

  const headers: Record<string, string> = { ...BROWSER_HEADERS as Record<string, string> };
  if (asExecutor) {
    const executors = ["wave", "Wave", "Xeno", "xeno", "Delta", "delta"];
    headers["identifyexecutor"] = executors[Math.floor(Math.random() * executors.length)];
    headers["User-Agent"] = "Roblox/WinInet";
  }

  try {
    const res = await fetch(url, { headers, signal: controller.signal });
    clearTimeout(tid);
    if (!res.ok) return null;
    return Buffer.from(await res.arrayBuffer());
  } catch {
    clearTimeout(tid);
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// URL / FILENAME HELPERS  (senvielle.py extract_links, get_filename_from_url)
// ─────────────────────────────────────────────────────────────────────────────

function extractFirstUrl(text: string): string | null {
  const m = text.match(/https?:\/\/[^\s"')\]]+/);
  if (!m) return null;
  let url = m[0].replace(/['\])]$/, "");
  if (url.endsWith(") )()")) url = url.slice(0, -4);
  return url;
}

function getFilenameFromUrl(url: string): string {
  let name = url.split("/").pop()?.split("?")[0] ?? "";
  name = decodeURIComponent(name);
  return name && name.includes(".") ? name : "script.lua";
}

function looksLikeCode(text: string): boolean {
  if (!text || /https?:\/\//i.test(text)) return false;
  return /\b(local|function|print|repeat|if|for|while|return|end)\b/.test(text);
}

function isHtml(buf: Buffer): boolean {
  const text = buf.slice(0, 5000).toString("utf8", 0, 5000);
  return /<!DOCTYPE|<html|<head|<body|<script/i.test(text);
}

function extractObfuscatedFromHtml(buf: Buffer): Buffer | null {
  const html = buf.toString("utf8");

  // Look for <script> tags with significant content
  const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)];
  for (const [, body] of scripts) {
    const s = body.trim();
    if (s.length > 100 && !/google|analytics|cdn\.jsdelivr|cloudflare/i.test(s)) {
      return Buffer.from(s, "utf8");
    }
  }

  // Inline base64-ish var
  const m = html.match(/(?:var|const|let)\s+\w+\s*=\s*["']([a-zA-Z0-9+/=]{500,})["']/);
  if (m) return Buffer.from(m[1], "utf8");

  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT EXTRACTION  (ported from senvielle.py _get_content)
// ─────────────────────────────────────────────────────────────────────────────

interface ContentResult {
  content: Buffer | null;
  filename: string;
  error: string | null;
}

function extractCodeblock(text: string): { code: string; lang: string } | null {
  // FIX #10: Prioritaskan codeblock dengan label lua/luau/kosong saja
  const m1 = text.match(/```(lua|luau|)\n([\s\S]*?)\n```/i);
  if (m1) return { code: m1[2].trim(), lang: m1[1] || "lua" };

  // Fallback: codeblock tanpa label — hanya jika isinya terlihat seperti kode Lua
  const m2 = text.match(/```\n?([\s\S]*?)\n?```/);
  if (m2) {
    const code = m2[1].trim();
    if (looksLikeCode(code)) return { code, lang: "lua" };
  }
  return null;
}

async function getContent(msg: Message, argLink?: string | null, asExecutor = false): Promise<ContentResult> {
  // FIX #21: Prioritas 1 - Check codeblock dari REPLY MESSAGE terlebih dahulu
  if (msg.reference?.messageId) {
    try {
      const ref = await msg.channel.messages.fetch(msg.reference.messageId);
      // 1a. Codeblock in replied message (PRIORITAS TERTINGGI)
      const refCb = extractCodeblock(ref.content ?? "");
      if (refCb) {
        return { content: Buffer.from(refCb.code, "utf8"), filename: `codeblock.${refCb.lang}`, error: null };
      }
      // 1b. Attachment on replied message
      if (ref.attachments.size > 0) {
        const att = ref.attachments.first()!;
        const ALLOWED_EXTENSIONS = new Set([".lua", ".luau", ".txt", ""]);
        const ext = path.extname(att.name ?? "").toLowerCase();
        if (!ALLOWED_EXTENSIONS.has(ext)) {
          return { content: null, filename: att.name ?? "file", error: `❌ Tipe file \`${ext}\` tidak didukung. Gunakan .lua, .luau, atau .txt` };
        }
        if (att.contentType && !att.contentType.startsWith("text/") && !att.contentType.includes("octet-stream")) {
          return { content: null, filename: att.name ?? "file", error: "❌ Binary files tidak didukung" };
        }
        if ((att.size ?? 0) <= MAX_FILE_SIZE) {
          const buf = await fetchUrl(att.url, 8_000, asExecutor);
          if (buf) return { content: buf, filename: att.name ?? "file", error: null };
        }
      }
      // 1c. URL in replied message
      const refUrl = extractFirstUrl(ref.content ?? "");
      if (refUrl) {
        const { safe, reason } = isSafeUrl(refUrl);
        if (safe) {
          const buf = await fetchUrl(refUrl, 8_000, asExecutor);
          if (buf && buf.length <= MAX_FILE_SIZE)
            return { content: buf, filename: getFilenameFromUrl(refUrl), error: null };
        }
      }
    } catch {}
  }

  // 0. Codeblock in current message
  const cb = extractCodeblock(msg.content);
  if (cb) {
    return { content: Buffer.from(cb.code, "utf8"), filename: `codeblock.${cb.lang}`, error: null };
  }

  // 0.5. Raw code snippet passed as argument (jika terlihat seperti kode, bukan command)
  if (argLink?.trim() && looksLikeCode(argLink.trim())) {
    return { content: Buffer.from(argLink.trim(), "utf8"), filename: "snippet.lua", error: null };
  }

  // 1. Attachment on current message
  if (msg.attachments.size > 0) {
    const att = msg.attachments.first()!;
    // FIX #9: Validasi ekstensi file attachment
    const ALLOWED_EXTENSIONS = new Set([".lua", ".luau", ".txt", ""]);
    const ext = path.extname(att.name ?? "").toLowerCase();
    if (!ALLOWED_EXTENSIONS.has(ext)) {
      return { content: null, filename: att.name ?? "file", error: `❌ Tipe file \`${ext}\` tidak didukung. Gunakan .lua, .luau, atau .txt` };
    }
    // Validasi MIME type jika tersedia
    if (att.contentType && !att.contentType.startsWith("text/") && !att.contentType.includes("octet-stream")) {
      return { content: null, filename: att.name ?? "file", error: "❌ Binary files tidak didukung" };
    }
    if ((att.size ?? 0) > MAX_FILE_SIZE)
      return { content: null, filename: att.name ?? "file", error: "File too large (max 5 MB)" };
    const buf = await fetchUrl(att.url, 8_000, asExecutor);
    if (!buf)
      return { content: null, filename: att.name ?? "file", error: "Failed to download attachment" };
    return { content: buf, filename: att.name ?? "file", error: null };
  }

  // 2. Explicit URL in argument
  if (argLink) {
    const url = extractFirstUrl(argLink) ?? argLink;
    const { safe, reason } = isSafeUrl(url);
    if (!safe) return { content: null, filename: "file", error: `Blocked URL: ${reason}` };

    const filename = getFilenameFromUrl(url);
    const buf = await fetchUrl(url, 8_000, asExecutor);
    if (buf) {
      if (buf.length > MAX_FILE_SIZE) return { content: null, filename, error: "File too large" };
      return { content: buf, filename, error: null };
    }
    return { content: null, filename, error: "Failed to fetch URL" };
  }

  return { content: null, filename: "file", error: "Provide a codeblock, URL, file, or reply to a message." };
}

// ─────────────────────────────────────────────────────────────────────────────
// LUA INTERPRETER DETECTION  (senvielle.py _find_lua)
// ─────────────────────────────────────────────────────────────────────────────

let _luaInterp: string | null = null;
let _luaHasE = false;

async function findLua(): Promise<string | null> {
  if (_luaInterp) return _luaInterp;
  for (const interp of LUA_INTERPRETERS) {
    try {
      const ok = await runProcess(interp, ["-v"], "", 3000);
      if (ok.code === 0 && ok.stderr !== "spawn error") {
        _luaInterp = interp;
        // Check -E flag support
        const eCheck = await runProcess(interp, ["-E", "-v"], "", 3000);
        _luaHasE = eCheck.code === 0 && eCheck.stderr !== "spawn error";
        logger.info({ interp, hasE: _luaHasE, source: FILE_NAME }, "Lua interpreter detected");
        return interp;
      }
    } catch {}
  }
  logger.warn({ source: FILE_NAME }, "No Lua interpreter found — install lua5.3, lua5.1, lua5.4, luajit, or lua");
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// PROCESS RUNNER
// ─────────────────────────────────────────────────────────────────────────────

interface ProcessResult {
  code: number;
  stdout: string;
  stderr: string;
}

function runProcess(cmd: string, args: string[], stdin: string, timeoutMs: number): Promise<ProcessResult> {
  return new Promise((resolve) => {
    let proc: ReturnType<typeof spawn>;
    try {
      proc = spawn(cmd, args);
    } catch {
      return resolve({ code: -1, stdout: "", stderr: "spawn error" });
    }
    const chunks: Buffer[] = [];
    const errChunks: Buffer[] = [];

    // FIX #2: Batasi output maksimal 10 MB untuk cegah memory bomb
    const MAX_OUTPUT_BYTES = 10 * 1024 * 1024;
    let totalBytes = 0;
    let outputKilled = false;

    if (stdin) proc.stdin.end(stdin, "utf8");
    else proc.stdin.end();

    proc.stdout.on("data", (d: Buffer) => {
      totalBytes += d.length;
      if (totalBytes > MAX_OUTPUT_BYTES) {
        if (!outputKilled) {
          outputKilled = true;
          proc.kill("SIGKILL");
          resolve({ code: -1, stdout: "", stderr: "output too large (>10MB) – process killed" });
        }
        return;
      }
      chunks.push(d);
    });
    proc.stderr.on("data", (d: Buffer) => errChunks.push(d));

    const tid = setTimeout(() => {
      proc.kill();
      resolve({ code: -1, stdout: "", stderr: "timeout" });
    }, timeoutMs);

    proc.on("close", (code) => {
      clearTimeout(tid);
      resolve({
        code: code ?? -1,
        stdout: Buffer.concat(chunks).toString("utf8"),
        stderr: Buffer.concat(errChunks).toString("utf8"),
      });
    });

    proc.on("error", () => {
      clearTimeout(tid);
      resolve({ code: -1, stdout: "", stderr: "spawn error" });
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// DUMPER  (ported from senvielle.py _run_dumper_blocking / run_dumper)
// – Calls sennv.lua as: lua[-E] sennv.lua <input_file> <output_file>
// ─────────────────────────────────────────────────────────────────────────────

interface DumperResult {
  dumped: Buffer | null;
  execMs: number;
  loops: number;
  lines: number;
  error: string | null;
}

async function runDumper(luaContent: Buffer): Promise<DumperResult> {
  // FIX #8: Batasi concurrent Lua execution dengan semaphore
  const release = await dumpSemaphore.acquire();
  try {
  const interp = await findLua();
  if (!interp) {
    return { dumped: null, execMs: 0, loops: 0, lines: 0, error: "No Lua interpreter found. Install lua5.3, lua5.1, lua5.4, luajit, or lua on the server." };
  }
  // FIX #1: Gunakan crypto-safe random (bukan Math.random yang lemah)
  const uid = randomBytes(16).toString("hex");
  const inputFile  = path.join(os.tmpdir(), `senv_in_${uid}.lua`);
  const outputFile = path.join(os.tmpdir(), `senv_out_${uid}.lua`);

  // FIX #1b: Validasi DUMPER_PATH tidak bisa escape direktori
  const SAFE_DUMPER_PATH = fs.realpathSync(DUMPER_PATH);
  const allowedRoot = path.resolve(__dirname, "..", "..");
  if (!SAFE_DUMPER_PATH.startsWith(allowedRoot)) {
    return { dumped: null, execMs: 0, loops: 0, lines: 0, error: "DUMPER_PATH resolves outside allowed directory" };
  }

  try {
    fs.writeFileSync(inputFile, luaContent);

    const args: string[] = [];
    if (_luaHasE) args.push("-E");
    args.push(DUMPER_PATH, inputFile, outputFile);

    const start = Date.now();
    const res = await runProcess(interp, args, "", DUMP_TIMEOUT_MS);
    const execMs = Date.now() - start;

    const stdout = res.stdout;

    let loops = 0, lines = 0;
    const lm = stdout.match(/Loops:\s*(\d+)/);
    if (lm) loops = parseInt(lm[1]);
    const lnm = stdout.match(/Lines:\s*(\d+)/);
    if (lnm) lines = parseInt(lnm[1]);

    if (fs.existsSync(outputFile)) {
      const dumped = fs.readFileSync(outputFile);
      return { dumped, execMs, loops, lines, error: null };
    }

    // Error parsing (same as senvielle.py)
    const luaErr = stdout.match(/\[LUA_LOAD_FAIL\][^\n]*/);
    let detail = luaErr
      ? luaErr[0].replace("[LUA_LOAD_FAIL] ", "").trim()
      : (res.stderr.trim().split("\n").pop() ?? "");

    const msg = detail ? `Output not generated: ${detail}` : "Output not generated";
    return { dumped: null, execMs: 0, loops: 0, lines: 0, error: msg };
  } catch (err: any) {
    if (err?.message?.includes("timeout")) {
      return { dumped: null, execMs: 0, loops: 0, lines: 0, error: "Dump timeout" };
    }
    return { dumped: null, execMs: 0, loops: 0, lines: 0, error: String(err) };
  } finally {
    for (const f of [inputFile, outputFile]) {
      try { if (fs.existsSync(f)) fs.unlinkSync(f); } catch {}
    }
  }
  } finally {
    // FIX #8: Selalu lepaskan semaphore setelah selesai
    release();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SENSITIVE OUTPUT REDACTION  (senvielle.py _redact_sensitive_output)
// ─────────────────────────────────────────────────────────────────────────────

// FIX 3: Tambah path absolut dumper & python script agar tidak bocor
// Ini mencakup nama file, path absolut, dan variasi path yang mungkin muncul di output
let _resolvedDumperPath = "";
let _resolvedPyPath = "";
try {
  _resolvedDumperPath = fs.realpathSync(DUMPER_PATH);
} catch { _resolvedDumperPath = DUMPER_PATH; }
try {
  _resolvedPyPath = fs.realpathSync(path.join(__dirname, "..", "senvielle.py"));
} catch { _resolvedPyPath = path.join(__dirname, "..", "senvielle.py"); }

const SENSITIVE_STRINGS = [
  path.basename(DUMPER_PATH),            // "sennv.lua"
  "senvielle.py",                        // python script name
  "senvielle",                           // tanpa ekstensi
  _resolvedDumperPath,                   // path absolut sennv.lua
  _resolvedPyPath,                       // path absolut senvielle.py
  path.dirname(_resolvedDumperPath),     // direktori induk
  "path getter",
  "attempting to get path",
  "paths if found",
  "catmio",
  "catlogger",
  "envlogger",
  "sandbox_e",
  "_sandbox_eR",
];

function redactSensitiveOutput(code: string): string {
  const result: string[] = [];
  for (const line of code.split("\n")) {
    const stripped = line.trim();

    if (stripped.startsWith("print(")) {
      const m = stripped.match(/^print\s*\(\s*["'](.+?)["']\s*\)/);
      if (m) {
        const inner = m[1].toLowerCase();
        if (SENSITIVE_STRINGS.some((s) => inner.includes(s.toLowerCase()))) continue;
      }
    }
    if (stripped.startsWith("--")) {
      const inner = stripped.slice(2).trim().toLowerCase();
      if (SENSITIVE_STRINGS.some((s) => inner.includes(s.toLowerCase()))) continue;
    }
    if (SENSITIVE_STRINGS.some((s) => line.includes(s))) continue;

    result.push(line);
  }
  return result.join("\n");
}

// ─────────────────────────────────────────────────────────────────────────────
// LUA PROCESSING PIPELINE  (all helpers ported from senvielle.py)
// ─────────────────────────────────────────────────────────────────────────────

// ── Strip loop markers ─────────────────────────────────────────────────────
function stripLoopMarkers(code: string): string {
  return code
    .split("\n")
    .filter((l) => !/^\s*--\s*Detected loops\s+\d+\s*$/.test(l))
    .join("\n");
}

// ── Normalize numeric counter suffixes (e.g. frame3 → frame) ─────────────
function normalizeCounters(line: string): string {
  return line.replace(/\b([a-z][A-Za-z_]*)\d+\b/g, "$1");
}

function normalizeAllCounters(code: string): string {
  return code.split("\n").map(normalizeCounters).join("\n");
}

// ── Collapse repeated loop-unrolled blocks ─────────────────────────────────
function collapseLoopUnrolls(code: string, maxReps = 3): string {
  const lines = code.split("\n");
  const n = lines.length;
  if (n === 0) return code;

  const normLines = lines.map(normalizeCounters);
  const result: string[] = [];
  let i = 0;

  while (i < n) {
    let bestBlockSize = 0, bestReps = 0;

    for (let blockSize = 1; blockSize < Math.min(51, n - i + 1); blockSize++) {
      if (i + blockSize > n) break;
      const normBlock = normLines.slice(i, i + blockSize);
      if (blockSize === 1) {
        const s = normBlock[0].trim();
        if (!s || s === "end" || s === "do" || s === "then") continue;
      }
      let reps = 1, j = i + blockSize;
      while (j + blockSize <= n) {
        const cmp = normLines.slice(j, j + blockSize);
        if (JSON.stringify(cmp) === JSON.stringify(normBlock)) { reps++; j += blockSize; }
        else break;
      }
      if (reps > maxReps && reps > bestReps) { bestReps = reps; bestBlockSize = blockSize; }
    }

    if (bestBlockSize && bestReps > maxReps) {
      for (let rep = 0; rep < maxReps; rep++) {
        result.push(...lines.slice(i + rep * bestBlockSize, i + (rep + 1) * bestBlockSize));
      }
      const omitted = bestReps - maxReps;
      const indent = lines[i].match(/^(\s*)/)?.[1] ?? "";
      i += bestReps * bestBlockSize;
      result.push(`${indent}-- [similar block repeated ${omitted} more time(s), omitted for clarity]`);
    } else {
      result.push(lines[i]);
      i++;
    }
  }
  return result.join("\n");
}

// ── Strip Lua comments (but keep catmio header) ────────────────────────────
const CATMIO_HEADER_RE = /^--\s*generated with catmio\b/i;

function stripInlineTrailingComment(line: string): string {
  let i = 0;
  const n = line.length;
  while (i < n) {
    const ch = line[i];
    if (ch === '"' || ch === "'") {
      const q = ch;
      i++;
      while (i < n) {
        const c2 = line[i];
        if (c2 === "\\") i += 2;
        else if (c2 === q) { i++; break; }
        else i++;
      }
    } else if (ch === "-" && i + 1 < n && line[i + 1] === "-") {
      return line.slice(0, i).trimEnd();
    } else {
      i++;
    }
  }
  return line;
}

function stripComments(code: string): string {
  const result: string[] = [];
  for (const line of code.split("\n")) {
    const stripped = line.trimStart();
    if (CATMIO_HEADER_RE.test(stripped)) { result.push(line); continue; }
    if (stripped.startsWith("--")) continue;
    result.push(stripInlineTrailingComment(line));
  }
  return result.join("\n");
}

// ── Fold string concatenations  ("a" .. "b" → "ab") ──────────────────────
function foldStringConcat(code: string): string {
  const re = /"((?:[^"\\]|\\.)*?)"\s*\.\.\s*"((?:[^"\\]|\\.)*?)"/g;
  let prev: string | null = null;
  while (prev !== code) {
    prev = code;
    code = code.replace(re, '"$1$2"');
  }
  return code;
}

// ── Inline single-use runtime constants ───────────────────────────────────
const RUNTIME_CONST_RE =
  /^[ \t]*local\s+(_ref_\d+|_url_\d+|_webhook_\d+)\s*=\s*("(?:[^"\\]|\\.)*")\s*$/gm;

function inlineSingleUseConstants(code: string): string {
  const constants: Map<string, string> = new Map();
  for (const m of code.matchAll(RUNTIME_CONST_RE)) {
    constants.set(m[1], m[2]);
  }
  if (constants.size === 0) return code;

  let result = code;
  for (const [name, value] of constants) {
    const pat = new RegExp(`\\b${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "g");
    const total = (result.match(pat) ?? []).length;
    if (total <= 1) {
      result = result.replace(
        new RegExp(`^[ \\t]*local\\s+${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*=\\s*"[^"]*"[ \\t]*$`, "m"),
        ""
      );
    }
  }
  return result;
}

// ── Collapse blank lines ───────────────────────────────────────────────────
function collapseBlankLines(code: string): string {
  return code.replace(/\n{3,}/g, "\n\n");
}

// ── Remove trailing whitespace ────────────────────────────────────────────
function removeTrailingWhitespace(code: string): string {
  return code.split("\n").map((l) => l.trimEnd()).join("\n");
}

// ── Deduplicate :Connect() bindings ───────────────────────────────────────
function dedupConnections(code: string): string {
  const lines = code.split("\n");
  const seen = new Set<string>();
  const result: string[] = [];
  let i = 0;
  while (i < lines.length) {
    const m = lines[i].match(/^\s*(\w[\w.]*\.\w+):Connect\s*\(/);
    if (m) {
      const key = m[1];
      if (seen.has(key)) {
        let depth = lines[i].split("(").length - lines[i].split(")").length;
        i++;
        while (i < lines.length && depth > 0) {
          depth += lines[i].split("(").length - lines[i].split(")").length;
          i++;
        }
        continue;
      }
      seen.add(key);
    }
    result.push(lines[i]);
    i++;
  }
  return result.join("\n");
}

// ── Beautify Lua (indent-based) ────────────────────────────────────────────
function beautifyLua(code: string): string {
  const lines = code.split("\n");
  const output: string[] = [];
  let indent = 0;

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) { output.push(""); continue; }

    const firstKw = line.match(/^(\w+)/)?.[1] ?? "";

    if (["end", "until"].includes(firstKw)) indent = Math.max(0, indent - 1);
    else if (["else", "elseif"].includes(firstKw)) indent = Math.max(0, indent - 1);

    output.push("    ".repeat(indent) + line);

    if (["else", "elseif"].includes(firstKw)) indent++;
    else if (["function", "do", "repeat"].includes(firstKw)) indent++;
    else if (["if", "for", "while"].includes(firstKw)) {
      if (/\b(then|do)\s*(?:--.*)?$/.test(line)) indent++;
    } else if (firstKw === "then") indent++;
    else if (/\bfunction\b/.test(line) && !/\bend\b\s*(?:--.*)?$/.test(line)) indent++;
  }

  return output.join("\n");
}

// ─────────────────────────────────────────────────────────────────────────────
// LUA COMPAT FIXER  (ported from senvielle.py _fix_lua_compat)
// Handles Luau compound assignment, operators, keyword aliasing
// ─────────────────────────────────────────────────────────────────────────────

const FLOORDIV_ASSIGN_RE  = /^([ \t]*)((?:[a-zA-Z_][\w]*(?:\.[a-zA-Z_][\w]*)*))\s*\/\/=\s*(.+)$/gm;
const CONCAT_ASSIGN_RE    = /^([ \t]*)((?:[a-zA-Z_][\w]*(?:\.[a-zA-Z_][\w]*)*))\s*\.\.=\s*(.+)$/gm;
const COMPOUND_ASSIGN_RE  = /^([ \t]*)((?:[a-zA-Z_][\w]*(?:\.[a-zA-Z_][\w]*)*))\s*([+\-*/%^])=\s*(.+)$/gm;

function fixLuaCompat(code: string): string {
  let out = convertLuauBacktickStrings(code);
  out = out.replace(FLOORDIV_ASSIGN_RE, "$1$2 = $2 // $3");
  out = out.replace(CONCAT_ASSIGN_RE,   "$1$2 = $2 .. $3");
  out = out.replace(COMPOUND_ASSIGN_RE, "$1$2 = $2 $3 $4");
  out = out.replace(/!=/g,              "~=");
  out = out.replace(/\s*&&\s*/g,        " and ");
  out = out.replace(/\s*\|\|\s*/g,      " or ");
  out = out.replace(/(?<!\w)!(?=[a-zA-Z_(])/g, "not ");
  out = out.replace(/\bnull\b/g,        "nil");
  out = out.replace(/\belse[ \t]+if\b/g,"elseif");
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// LUAU BACKTICK STRING CONVERTER  (senvielle.py _convert_luau_backtick_strings)
// ─────────────────────────────────────────────────────────────────────────────

function convertLuauBacktickStrings(code: string): string {
  const result: string[] = [];
  let i = 0;
  const n = code.length;

  while (i < n) {
    const ch = code[i];

    // Long bracket
    if (ch === "[" && i + 1 < n && (code[i + 1] === "[" || code[i + 1] === "=")) {
      let j = i + 1, lvl = 0;
      while (j < n && code[j] === "=") { lvl++; j++; }
      if (j < n && code[j] === "[") {
        const close = "]" + "=".repeat(lvl) + "]";
        const end = code.indexOf(close, j + 1);
        if (end !== -1) { result.push(code.slice(i, end + close.length)); i = end + close.length; continue; }
      }
    }

    // Comment
    if (ch === "-" && i + 1 < n && code[i + 1] === "-") {
      const nl = code.indexOf("\n", i);
      const ep = nl === -1 ? n : nl + 1;
      result.push(code.slice(i, ep)); i = ep; continue;
    }

    // Regular string
    if (ch === '"' || ch === "'") {
      const q = ch; let j = i + 1;
      while (j < n) {
        const c2 = code[j];
        if (c2 === "\\") j += 2;
        else if (c2 === q) { j++; break; }
        else if (c2 === "\n") break;
        else j++;
      }
      result.push(code.slice(i, j)); i = j; continue;
    }

    // Backtick string → double-quoted
    if (ch === "`") {
      let j = i + 1;
      const buf: string[] = [];
      while (j < n && code[j] !== "`") {
        const c2 = code[j];
        if (c2 === "\\" && j + 1 < n) { buf.push("\\", code[j + 1]); j += 2; }
        else if (c2 === '"')  { buf.push('\\"'); j++; }
        else if (c2 === "\n") { buf.push("\\n"); j++; }
        else if (c2 === "\r") { buf.push("\\r"); j++; }
        else { buf.push(c2); j++; }
      }
      if (j < n) j++;
      result.push('"' + buf.join("") + '"'); i = j; continue;
    }

    result.push(ch); i++;
  }

  return result.join("");
}

// ─────────────────────────────────────────────────────────────────────────────
// LUNR v1.0.7 SPECIFIC DEOBFUSCATION  (senvielle.py _detect_lunr, etc.)
// ─────────────────────────────────────────────────────────────────────────────

const LUNR_HEADER_RE = /--\s*This file was protected using Lunr\b/i;

function detectLunr(code: string): string | null {
  if (!LUNR_HEADER_RE.test(code.slice(0, 1000))) return null;
  const m = code.slice(0, 1000).match(/Lunr\s+v([\d.]+)/i);
  return m ? m[1] : "unknown";
}

const LUNR_WHILE_FALSE_RE = /\bwhile\s+false\s+do\b/g;
const LUNR_CONST_IF_RE    = /\bif\s+(-?\d+(?:\.\d+)?)\s*(>|<|>=|<=|==|~=)\s*(-?\d+(?:\.\d+)?)\s+then\b/g;

function evalConstCmp(lhs: string, op: string, rhs: string): boolean | null {
  const l = parseFloat(lhs), r = parseFloat(rhs);
  if (isNaN(l) || isNaN(r)) return null;
  if (op === ">")  return l > r;
  if (op === "<")  return l < r;
  if (op === ">=") return l >= r;
  if (op === "<=") return l <= r;
  if (op === "==") return l === r;
  if (op === "~=") return l !== r;
  return null;
}

function stripLunrDeadBlocks(code: string): string {
  // Simple heuristic: remove while false do ... end and always-false if blocks
  code = code.replace(/\bwhile\s+false\s+do\b[\s\S]*?\bend\b/g, "");
  code = code.replace(
    /\bif\s+(-?\d+(?:\.\d+)?)\s*(>|<|>=|<=|==|~=)\s*(-?\d+(?:\.\d+)?)\s+then\b[\s\S]*?\bend\b/g,
    (_, lhs, op, rhs) => {
      const res = evalConstCmp(lhs, op, rhs);
      return res === false ? "" : _;
    }
  );
  return code;
}

const LUNR_JUNK_LOCAL_RE =
  /^[ \t]*local\s+[a-zA-Z_][a-zA-Z0-9_]*\s*=\s*(?:(?:[-()\\d.^, \t]*[+\-*/^][-()\\d+\-*/.^, \t]+)|(?:true|false|nil)|"(?:All warfare|Opportunities multiply|In the midst|The supreme art|There is no instance|To know your Enemy|Engage people|Let your plans|If you know the enemy|Supreme excellence)[^"]*")\s*;?[ \t]*$/gim;

function stripLunrJunkLocals(code: string): string {
  return code.replace(LUNR_JUNK_LOCAL_RE, "");
}

function applyLunrPreprocessing(code: string): string {
  code = convertLuauBacktickStrings(code);
  code = stripLunrDeadBlocks(code);
  code = stripLunrJunkLocals(code);
  code = collapseBlankLines(code);
  return code;
}

// ─────────────────────────────────────────────────────────────────────────────
// HEURISTIC FIX PIPELINE  (senvielle.py _run_heuristic_fix_pipeline)
// ─────────────────────────────────────────────────────────────────────────────

const OBFUSCATION_INDICATOR_RE =
  /loadstring\s*\(\s*game:HttpGet|getfenv\s*\(|setfenv\s*\(|newcclosure|hookmetamethod|while\s+true\s+do|while\s+false\s+do|_0x[0-9a-fA-F]+|\\x[0-9a-fA-F]{2}|bit32?\.(?:bxor|band|bor)|elseif\s+[^\n]{120,}|function\s*\(\s*\.\.\.\s*\)\s*return\s+function/i;

function shouldUseAggressiveHeuristics(code: string): boolean {
  if (!code) return false;
  if (OBFUSCATION_INDICATOR_RE.test(code)) return true;
  const lines = code.split("\n");
  const veryLong   = lines.filter((l) => l.length > 260).length;
  const denseNames = lines.filter((l) => l.length > 120 && /[A-Za-z_][A-Za-z0-9_]*\d{3,}/.test(l)).length;
  const compactNoise = lines.filter((l) => l && (l.split(";").length >= 4 || l.split("\\").length >= 4)).length;
  return veryLong >= 8 || denseNames >= 12 || compactNoise >= 20;
}

function runHeuristicFixPipeline(code: string): string {
  code = fixLuaCompat(code);
  if (shouldUseAggressiveHeuristics(code)) {
    code = foldStringConcat(code);
    code = inlineSingleUseConstants(code);
    code = dedupConnections(code);
    code = collapseLoopUnrolls(code);
  }
  code = beautifyLua(code);
  code = collapseBlankLines(code);
  code = removeTrailingWhitespace(code);
  return code;
}

// ─────────────────────────────────────────────────────────────────────────────
// ROBLOX ENVIRONMENT ENHANCEMENTS
// ─────────────────────────────────────────────────────────────────────────────

// Common Roblox environment functions to inject
const ROBLOX_ENV_FUNCTIONS = `
-- Roblox Environment Functions
local function_env_roblox = {}

-- Game service getters
function_env_roblox.GetWorkspace = function() return game:GetService("Workspace") end
function_env_roblox.GetPlayers = function() return game:GetService("Players") end
function_env_roblox.GetLighting = function() return game:GetService("Lighting") end
function_env_roblox.GetReplicatedStorage = function() return game:GetService("ReplicatedStorage") end
function_env_roblox.GetReplicatedFirst = function() return game:GetService("ReplicatedFirst") end
function_env_roblox.GetServerStorage = function() return game:GetService("ServerStorage") end
function_env_roblox.GetServerScriptService = function() return game:GetService("ServerScriptService") end
function_env_roblox.GetStarterPlayer = function() return game:GetService("StarterPlayer") end
function_env_roblox.GetStarterGui = function() return game:GetService("StarterGui") end
function_env_roblox.GetStarterPack = function() return game:GetService("StarterPack") end
function_env_roblox.GetTeams = function() return game:GetService("Teams") end
function_env_roblox.GetSoundService = function() return game:GetService("SoundService") end
function_env_roblox.GetChat = function() return game:GetService("Chat") end
function_env_roblox.GetTextChatService = function() return game:GetService("TextChatService") end
function_env_roblox.GetUserInputService = function() return game:GetService("UserInputService") end
function_env_roblox.GetContextActionService = function() return game:GetService("ContextActionService") end
function_env_roblox.GetRunService = function() return game:GetService("RunService") end
function_env_roblox.GetTweenService = function() return game:GetService("TweenService") end
function_env_roblox.GetHttpService = function() return game:GetService("HttpService") end
function_env_roblox.GetMarketplaceService = function() return game:GetService("MarketplaceService") end

-- Player utilities
function_env_roblox.GetLocalPlayer = function() return game:GetService("Players").LocalPlayer end
function_env_roblox.GetPlayersList = function() return game:GetService("Players"):GetPlayers() end
function_env_roblox.GetCharacter = function() return game:GetService("Players").LocalPlayer.Character end
function_env_roblox.GetHumanoid = function() local char = game:GetService("Players").LocalPlayer.Character if char then return char:FindFirstChild("Humanoid") end return nil end

-- Instance utilities
function_env_roblox.FindFirstChild = function(instance, name, recursive) if recursive then return instance:FindFirstChild(name, true) else return instance:FindFirstChild(name) end end
function_env_roblox.GetDescendants = function(instance) return instance:GetDescendants() end
function_env_roblox.Clone = function(instance) return instance:Clone() end
function_env_roblox.Destroy = function(instance) instance:Destroy() end

-- Task utilities
function_env_roblox.Wait = task.wait
function_env_roblox.Spawn = task.spawn
function_env_roblox.Defer = task.defer
function_env_roblox.Delay = task.delay

-- Global environment variables
_G = _G or {}
_G.game = game
_G.workspace = game:GetService("Workspace")
_G.Players = game:GetService("Players")
_G.Lighting = game:GetService("Lighting")
_G.ReplicatedStorage = game:GetService("ReplicatedStorage")
_G.ReplicatedFirst = game:GetService("ReplicatedFirst")
_G.ServerStorage = game:GetService("ServerStorage")
_G.ServerScriptService = game:GetService("ServerScriptService")
_G.StarterPlayer = game:GetService("StarterPlayer")
_G.StarterGui = game:GetService("StarterGui")
_G.StarterPack = game:GetService("StarterPack")
_G.Teams = game:GetService("Teams")
_G.SoundService = game:GetService("SoundService")
_G.Chat = game:GetService("Chat")
_G.TextChatService = game:GetService("TextChatService")
_G.UserInputService = game:GetService("UserInputService")
_G.ContextActionService = game:GetService("ContextActionService")
_G.RunService = game:GetService("RunService")
_G.TweenService = game:GetService("TweenService")
_G.Debris = game:GetService("Debris")
_G.InsertService = game:GetService("InsertService")
_G.TeleportService = game:GetService("TeleportService")
_G.HttpService = game:GetService("HttpService")
_G.MarketplaceService = game:GetService("MarketplaceService")
_G.PathfindingService = game:GetService("PathfindingService")
_G.CollectionService = game:GetService("CollectionService")

-- Inject function_env_roblox into global scope
for k, v in pairs(function_env_roblox) do
    _G[k] = v
end

-- Common aliases
_G.getrenv = getrenv or function() return _G end
_G.getgenv = getgenv or function() return _G end
_G.getfenv = getfenv or function() return _G end
_G.setfenv = setfenv or function(f, env) return f end

print("[Roblox Environment] Loaded successfully")
`;

// Inject Roblox environment into Lua code
function injectRobloxEnvironment(code: string): string {
  // Check if code already has Roblox environment
  if (code.includes("function_env_roblox") || code.includes("game:GetService")) {
    return code;
  }
  
  // Inject at the beginning of the script
  return ROBLOX_ENV_FUNCTIONS + "\n\n-- User code below\n" + code;
}

// ─────────────────────────────────────────────────────────────────────────────
// FAKE EXECUTOR FUNCTIONS INJECTION
// Provides mock functions for KRNL, Synapse, Delta, and other executors
// ─────────────────────────────────────────────────────────────────────────────

const FAKE_EXECUTOR_FUNCTIONS = `
-- ============================================================================
-- MOCK EXECUTOR FUNCTIONS — For deobfuscation & analysis
-- Provides stubs for KRNL, Synapse, Delta, and other executors
-- ============================================================================

-- Environment getters/setters
getgenv = getgenv or function() return _G end
getrenv = getrenv or function() return _G end
getfenv = getfenv or function(level) return _G end
setfenv = setfenv or function(f, env) return f end
getgc = getgc or function(include_threads) return {} end
getreg = getreg or function() return {} end
getregistry = getregistry or function() return {} end
getmenv = getmenv or function() return {} end

-- Instance utilities
getinstances = getinstances or function() return {} end
getnilinstances = getnilinstances or function() return {} end
getscripts = getscripts or function() return {} end
getcallingscript = getcallingscript or function() return nil end
getrunningscripts = getrunningscripts or function() return {} end
gethui = gethui or function() return {} end
gethiddenui = gethiddenui or function() return {} end
getloadedmodules = getloadedmodules or function() return {} end

-- Metatable/Closure operations
getrawmetatable = getrawmetatable or function(obj) return getmetatable(obj) or {} end
setrawmetatable = setrawmetatable or function(obj, mt) return setmetatable(obj, mt) end
hookfunction = hookfunction or function(old, new) return old end
hookmetamethod = hookmetamethod or function(obj, method, hook) return old end
newcclosure = newcclosure or function(f) return f end
newlclosure = newlclosure or function(f) return f end
iscclosure = iscclosure or function(f) return false end
islclosure = islclosure or function(f) return true end
checkcaller = checkcaller or function() return true end
clonefunction = clonefunction or function(f) return f end
restorefunction = restorefunction or function(f) return f end
replaceclosure = replaceclosure or function(old, new) return new end
ishooked = ishooked or function(f) return false end
getnamecallmethod = getnamecallmethod or function() return nil end
setnamecallmethod = setnamecallmethod or function(method) return end

-- Debug/Introspection
getconstants = getconstants or function(f) return {} end
getconstant = getconstant or function(f, idx) return nil end
setconstant = setconstant or function(f, idx, value) return end
getupvalues = getupvalues or function(f) return {} end
getupvalue = getupvalue or function(f, idx) return nil, nil end
setupvalue = setupvalue or function(f, idx, value) return nil end
getproto = getproto or function(f, idx) return nil end
getprotos = getprotos or function(f) return {} end
setproto = setproto or function(f, idx, proto) return end
getstack = getstack or function(f, idx) return nil end
setstack = setstack or function(f, idx, value) return end
getinfo = getinfo or function(f) return debug.getinfo(f) end
decompile = decompile or function(f) return "-- Cannot decompile" end
dump_string = dump_string or function(str) return string.dump(load(str)) end
dump_file = dump_file or function(path) return nil end
dumpstring = dumpstring or dump_string

-- Network/Identity
isnetworkowner = isnetworkowner or function(instance) return true end
getthreadidentity = getthreadidentity or function() return 8 end
setthreadidentity = setthreadidentity or function(id) return end
getidentity = getidentity or function() return 8 end
setidentity = setidentity or function(id) return end

-- Fire events
fireclickdetector = fireclickdetector or function(detector, distance) return end
fireproximityprompt = fireproximityprompt or function(prompt, distance) return end
firetouchinterest = firetouchinterest or function(part1, part2, touch) return end
firesignal = firesignal or function(signal, ...) return end
getconnections = getconnections or function(signal) return {} end

-- File I/O
readfile = readfile or function(path) return nil end
writefile = writefile or function(path, content) return false end
appendfile = appendfile or function(path, content) return false end
loadfile = loadfile or function(path) return nil end
listfiles = listfiles or function(path) return {} end
isfile = isfile or function(path) return false end
isfolder = isfolder or function(path) return false end
makefolder = makefolder or function(path) return false end
delfolder = delfolder or function(path) return false end
delfile = delfile or function(path) return false end
dofile = dofile or function(path) return nil end

-- Clipboard
setclipboard = setclipboard or function(text) return end
getclipboard = getclipboard or function() return "" end
toclipboard = toclipboard or setclipboard

-- HTTP/Network
request = request or function(options) return nil end
http_request = http_request or request
HttpPost = HttpPost or function(url, data, headers) return nil end
syn_request = syn_request or request

-- Input
mouse1click = mouse1click or function() return end
mouse2click = mouse2click or function() return end
mouse1press = mouse1press or function() return end
mouse1release = mouse1release or function() return end
mouse2press = mouse2press or function() return end
mouse2release = mouse2release or function() return end
keypress = keypress or function(key) return end
keyrelease = keyrelease or function(key) return end
keyclick = keyclick or function(key) return end
mousemoveabs = mousemoveabs or function(x, y) return end
mousemoverel = mousemoverel or function(x, y) return end
mousescroll = mousescroll or function(amount) return end

-- Window
isrbxactive = isrbxactive or function() return true end
iswindowactive = iswindowactive or function() return true end
isgameactive = isgameactive or function() return true end
setwindowactive = setwindowactive or function() return end

-- Executor identification
identifyexecutor = identifyexecutor or function() return "Lua Interpreter (Mock)" end
getexecutorname = getexecutorname or function() return "Standalone Lua" end
getexecutorversion = getexecutorversion or function() return "5.1/5.3/5.4" end

-- Teleport/Queue
queue_on_teleport = queue_on_teleport or function(script) end
queueonteleport = queueonteleport or queue_on_teleport

-- Utilities
protect_gui = protect_gui or function(gui) return end
unprotect_gui = unprotect_gui or function(gui) return end
protectgui = protect_gui
unprotectgui = unprotect_gui
setreadonly = setreadonly or function(t, readonly) return end
isreadonly = isreadonly or function(t) return false end

-- Drawing/Console
Drawing = Drawing or {}
Drawing.new = Drawing.new or function(typ) return {} end
rconsoleprint = rconsoleprint or function(...) print(...) end
rconsoleclear = rconsoleclear or function() end

-- KRNL
krnl = krnl or {}
krnl.load_file = krnl.load_file or function(path) end
krnl.load_bytes = krnl.load_bytes or function(bytes) end
krnl.decompile = krnl.decompile or function(f) end

-- Synapse
syn = syn or {}
syn.request = syn.request or request

-- Delta
delta = delta or {}
delta.loadfile = delta.loadfile or function(path) end

-- ScriptWare
scriptware = scriptware or {}
scriptware.loadfile = scriptware.loadfile or function(path) end

print("[Fake Executor Functions] Loaded for deobfuscation")
`;

function injectFakeExecutorFunctions(code: string): string {
  // Check if already injected
  if (code.includes("Fake Executor Functions") || code.includes("[Fake Executor Functions]")) {
    return code;
  }
  
  // Inject at beginning
  return FAKE_EXECUTOR_FUNCTIONS + "\n\n-- User code below\n" + code;
}

// ─────────────────────────────────────────────────────────────────────────────
// PASTEFY UPLOAD  (senvielle.py upload_to_pastefy)
// ─────────────────────────────────────────────────────────────────────────────

async function uploadToPastefy(content: string, title = "Dumped Script"): Promise<{ url: string | null; raw: string | null }> {
  try {
    const res = await fetch("https://pastefy.app/api/v2/paste", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, content, visibility: "PUBLIC" }),
    });
    if (res.ok) {
      const data = await res.json();
      const pid = (data?.paste?.id) ?? data?.id;
      if (pid) return { url: `https://pastefy.app/${pid}`, raw: `https://pastefy.app/${pid}/raw` };
    }
  } catch (err) {
    logger.warn({ err, source: FILE_NAME }, "Pastefy upload failed");
  }
  return { url: null, raw: null };
}

// ─────────────────────────────────────────────────────────────────────────────
// FULL DUMP PIPELINE  (orchestrates dumper + post-processing)
// ─────────────────────────────────────────────────────────────────────────────

async function fullDumpPipeline(
  content: Buffer,
  statusMsg: Message
): Promise<{ text: string | null; execMs: number; error: string | null }> {
  // FIX #23: Inject both Roblox environment AND fake executor functions
  let src = content.toString("utf8");
  src = injectFakeExecutorFunctions(src);  // Inject fake executor functions first
  src = injectRobloxEnvironment(src);      // Then inject Roblox environment
  content = Buffer.from(src, "utf8");

  // Pre-process: Luau compat fix
  const fixed = fixLuaCompat(src);
  if (fixed !== src) content = Buffer.from(fixed, "utf8");

  // Lunr detection
  const lunrVer = detectLunr(src);
  if (lunrVer) {
    await statusMsg.edit(`Lunr v${lunrVer} detected – stripping dead code...`);
    const cleaned = applyLunrPreprocessing(src);
    if (cleaned !== src) { src = cleaned; content = Buffer.from(cleaned, "utf8"); }
  }

  let { dumped, execMs, error } = await runDumper(content);

  // Retry with heuristic fix if first attempt failed
  if (error && !dumped) {
    const heurFixed = runHeuristicFixPipeline(src);
    if (heurFixed !== src) {
      const retry = await runDumper(Buffer.from(heurFixed, "utf8"));
      if (!retry.error && retry.dumped) {
        ({ dumped, execMs, error } = { ...retry, error: null });
      }
    }
  }

  if (error || !dumped) return { text: null, execMs, error: error ?? "Unknown error" };

  // Post-process output
  let text = dumped.toString("utf8");
  text = stripLoopMarkers(text);
  text = redactSensitiveOutput(text);
  text = collapseLoopUnrolls(text);
  text = foldStringConcat(text);
  text = inlineSingleUseConstants(text);
  text = dedupConnections(text);
  text = normalizeAllCounters(text);
  text = collapseLoopUnrolls(text);
  text = stripComments(text);
  text = collapseBlankLines(text);
  text = removeTrailingWhitespace(text);
  text = redactSensitiveOutput(text); // final pass

  return { text, execMs, error: null };
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .l  (deobfuscate / dump)
// ─────────────────────────────────────────────────────────────────────────────

export async function luaCommand(msg: Message, argLink?: string) {
  // FIX #6: Gunakan per-command rate limit untuk .l (10 detik)
  const remaining = checkRateLimit(msg.author.id, ".l");
  if (remaining > 0) {
    await sendLogEmbed(msg.client, "warn", "Rate limited (.l)",
      `User ${msg.author.tag} (${msg.author.id}) hit rate limit (${remaining.toFixed(1)}s remaining)`,
      { user: msg.author.tag, guild: msg.guild?.name ?? "DM" });
    return msg.reply(`⏳ Slow down, wait **${remaining.toFixed(1)}s**`);
  }

  // FIX #8: Beri tahu user jika semaphore penuh
  if (dumpSemaphore.atCapacity) {
    await msg.reply("⏳ Server sedang sibuk memproses 3 dump bersamaan, mohon tunggu...");
  }

  // FIX #22: Track error state untuk tahu apakah statusMsg harus dihapus
  let statusMsg: Message | null = null;
  let hasError = false;
  try {
    statusMsg = await withRetry(() => msg.channel.send("⏳ dumping..."), ".l statusMsg");

    const { content, filename, error: fetchErr } = await getContent(msg, argLink);
    if (fetchErr || !content) {
      hasError = true;
      await statusMsg.edit(fetchErr ?? "Failed to get content");
      return;
    }

    const { text, execMs, error } = await fullDumpPipeline(content, statusMsg);

    if (error || !text) {
      hasError = true;
      try {
        const failDir = path.join(process.cwd(), "data", "failed_deobf");
        if (!fs.existsSync(failDir)) fs.mkdirSync(failDir, { recursive: true });
        fs.writeFileSync(path.join(failDir, `failed_${Date.now()}.lua`), content);
        logger.info("Saved failed deobf script for auto-learning analysis");
      } catch (e) {
        logger.error({ err: e }, "Failed to save failed deobf script");
      }
      await sendLogEmbed(msg.client, "error", "Dump failed (.l)",
        error ?? "Unknown error",
        { user: msg.author.tag, file: filename, source: FILE_NAME });
      // FIX #22: Ubah statusMsg menjadi error message yang PERMANENT (tidak dihapus)
      await statusMsg.edit(`❌ **Error:** ${error}`);
      return;
    }

    const { raw } = await uploadToPastefy(text, filename);

    await sendLogEmbed(msg.client, "info", "Dump succeeded (.l)",
      `User ${msg.author.tag} dumped \`${filename}\` in ${execMs.toFixed(0)}ms`,
      { user: msg.author.tag, file: filename, paste: raw ?? "none", source: FILE_NAME });

    // FIX #20: Output extension yang benar + random 5-char suffix anti-expose
    const baseName = path.basename(filename, path.extname(filename));
    const randSuffix = randomBytes(3).toString("hex").slice(0, 5); // 5 karakter hex acak
    const outName = `${baseName}_${randSuffix}_dumped.lua`;

    const msgContent = `✅ done in **${execMs.toFixed(2)}ms**${raw ? ` | ${raw}` : ""}`;
    await withRetry(() =>
      msg.reply({
        content: msgContent,
        files: [new AttachmentBuilder(Buffer.from(text, "utf8"), { name: outName })],
      }), ".l reply"
    );
    // FIX #22: Hapus status message hanya setelah sukses
    await statusMsg.delete().catch(() => {});
  } catch (err) {
    hasError = true;
    logger.error({ err, source: FILE_NAME }, "Unhandled error in luaCommand");
    // FIX #22: Hapus status message yang lama, reply dengan error message baru
    if (statusMsg) {
      await statusMsg.delete().catch(() => {});
    }
    await msg.reply("❌ Internal error. Coba lagi.").catch(() => {});
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .bf  (beautify)
// ─────────────────────────────────────────────────────────────────────────────

export async function beautifyCommand(msg: Message, argLink?: string) {
  const remaining = checkRateLimit(msg.author.id);
  if (remaining > 0) return msg.reply(`⏳ Wait **${remaining.toFixed(1)}s**`);

  const statusMsg = await withRetry(() => msg.channel.send("⏳ beautifying..."));
  const { content, filename, error: fetchErr } = await getContent(msg, argLink);
  if (fetchErr || !content) { await statusMsg.edit(fetchErr ?? "No content"); return; }

  let lua = content.toString("utf8");
  lua = injectFakeExecutorFunctions(lua);  // Add fake executor functions
  lua = injectRobloxEnvironment(lua);      // Add Roblox environment
  const beautified = beautifyLua(lua);

  const { raw } = await uploadToPastefy(beautified, `[BF] ${filename}`);
  await statusMsg.delete().catch(() => {});

  await sendLogEmbed(msg.client, "info", "Beautify (.bf)",
    `User ${msg.author.tag} beautified \`${filename}\``,
    { user: msg.author.tag, file: filename, source: FILE_NAME });

  await withRetry(() =>
    msg.reply({
      content: `✅ beautified${raw ? ` | ${raw}` : ""}`,
      files: [
        new AttachmentBuilder(Buffer.from(beautified, "utf8"), {
          name: `${path.basename(filename, path.extname(filename))}_bf.lua`,
        }),
      ],
    })
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .darklua  (interactive transformation menu)
// Ported from senvielle.py _DarkluaView
// ─────────────────────────────────────────────────────────────────────────────

const DARKLUA_OPTIONS = [
  { label: "Remove Comments",            value: "strip_comments",   description: "Remove all Lua comments" },
  { label: "Rename Variables",           value: "rename_vars",      description: "Rename Instance.new() variables" },
  { label: "Fold String Concatenations", value: "fold_strings",     description: 'Collapse "a" .. "b" into "ab"' },
  { label: "Inline Single-Use Constants",value: "inline_constants", description: "Inline constants used only once" },
  { label: "Beautify / Reformat",        value: "beautify",         description: "Normalize indentation" },
  { label: "Fix Syntax Errors",          value: "fix_syntax",       description: "Heuristic Lua syntax repair" },
  { label: "Inject Roblox Env",          value: "inject_roblox",    description: "Add Roblox environment functions" },
];

export async function darkluaCommand(msg: Message, argLink?: string) {
  const remaining = checkRateLimit(msg.author.id);
  if (remaining > 0) return msg.reply(`⏳ Wait **${remaining.toFixed(1)}s**`);

  const statusMsg = await withRetry(() => msg.channel.send("⏳ downloading..."));
  const { content, filename, error: fetchErr } = await getContent(msg, argLink);
  if (fetchErr || !content) { await statusMsg.edit(fetchErr ?? "No content"); return; }

  let luaText = content.toString("utf8");
  await statusMsg.delete().catch(() => {});

  const selectMenu = new StringSelectMenuBuilder()
    .setCustomId("darklua_select")
    .setPlaceholder("Choose transformations…")
    .setMinValues(1)
    .setMaxValues(DARKLUA_OPTIONS.length)
    .addOptions(
      DARKLUA_OPTIONS.map((o) =>
        new StringSelectMenuOptionBuilder().setLabel(o.label).setValue(o.value).setDescription(o.description)
      )
    );

  const applyBtn = new ButtonBuilder()
    .setCustomId("darklua_apply")
    .setLabel("Apply")
    .setStyle(ButtonStyle.Primary);

  const row1 = new ActionRowBuilder<StringSelectMenuBuilder>().addComponents(selectMenu);
  const row2 = new ActionRowBuilder<ButtonBuilder>().addComponents(applyBtn);

  const embed = new EmbedBuilder()
    .setColor(COLOR_INFO)
    .setTitle("darklua")
    .setDescription(`File: **${filename}**  •  ${luaText.length.toLocaleString()} chars\n\nSelect the transformations to apply, then click **Apply**.`)
    .setFooter({ text: "🐱 • Expires in 2 minutes" });

  const menuMsg = await withRetry(() => msg.reply({ embeds: [embed], components: [row1, row2] }));

  let selected: string[] = [];

  const collector = menuMsg.createMessageComponentCollector({ time: 120_000 });

  collector.on("collect", async (interaction) => {
    if (interaction.user.id !== msg.author.id) {
      await interaction.reply({ content: "Only the command author can use this menu.", ephemeral: true });
      return;
    }
    if (interaction.customId === "darklua_select") {
      selected = (interaction as StringSelectMenuInteraction).values;
      await interaction.deferUpdate();
    } else if (interaction.customId === "darklua_apply") {
      if (selected.length === 0) {
        await interaction.reply({ content: "Please select at least one transformation first.", ephemeral: true });
        return;
      }
      collector.stop("applied");

      await interaction.update({ content: "⏳ processing…", embeds: [], components: [] });

      let code = luaText;
      // Inject fake functions and Roblox environment
      code = injectFakeExecutorFunctions(code);
      code = injectRobloxEnvironment(code);
      
      const selectedSet = new Set(selected);

      const ORDER = ["strip_comments", "fix_syntax", "rename_vars", "fold_strings", "inline_constants", "beautify", "inject_roblox"];
      for (const key of ORDER) {
        if (!selectedSet.has(key)) continue;
        if (key === "strip_comments")     code = stripComments(code);
        else if (key === "fix_syntax")    code = runHeuristicFixPipeline(code);
        else if (key === "fold_strings")  code = foldStringConcat(code);
        else if (key === "inline_constants") code = inlineSingleUseConstants(code);
        else if (key === "beautify")      code = beautifyLua(code);
        else if (key === "inject_roblox") code = injectRobloxEnvironment(code);
      }

      const { raw } = await uploadToPastefy(code, `[darklua] ${filename}`);
      const labels = DARKLUA_OPTIONS.filter((o) => selectedSet.has(o.value)).map((o) => o.label).join(", ");

      await sendLogEmbed(msg.client, "info", "Darklua (.darklua)",
        `User ${msg.author.tag} applied [${labels}] to \`${filename}\``,
        { user: msg.author.tag, file: filename, source: FILE_NAME });

      const resultEmbed = new EmbedBuilder()
        .setColor(COLOR_OK)
        .setTitle("darklua")
        .setDescription(`Applied: **${labels}**\n${raw ? `Paste: ${raw}` : "Paste upload failed"}`);

      await interaction.followup({
        embeds: [resultEmbed],
        files: [
          new AttachmentBuilder(Buffer.from(code, "utf8"), {
            name: `${path.basename(filename, path.extname(filename))}_darklua.lua`,
          }),
        ],
      });
    }
  });

  collector.on("end", async (_, reason) => {
    if (reason !== "applied") {
      await menuMsg.edit({ components: [] }).catch(() => {});
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .get  (fetch URL / attachment and re-upload)
// ─────────────────────────────────────────────────────────────────────────────

export async function getCommand(msg: Message, argLink?: string) {
  const statusMsg = await withRetry(() => msg.channel.send("⏳ downloading..."));

  if (argLink) {
    const url = extractFirstUrl(argLink) ?? argLink;
    const { safe, reason } = isSafeUrl(url);
    if (!safe) {
      await sendLogEmbed(msg.client, "warn", "SSRF blocked (.get)",
        `User ${msg.author.tag} tried blocked URL: ${url} (${reason})`,
        { source: FILE_NAME });
      await statusMsg.edit(`❌ Blocked URL: ${reason}`);
      return;
    }
  }

  const { content, filename, error: fetchErr } = await getContent(msg, argLink, true);
  if (fetchErr || !content) { await statusMsg.edit(fetchErr ?? "No content"); return; }

  let buf = content;
  let outFilename = filename;

  if (isHtml(buf)) {
    await statusMsg.edit("HTML detected – extracting obfuscated code...");
    const extracted = extractObfuscatedFromHtml(buf);
    if (extracted) { buf = extracted; outFilename = path.basename(filename, path.extname(filename)) + "_extracted.txt"; }
    else outFilename = path.basename(filename, path.extname(filename)) + "_raw.html";
  } else if (!outFilename.endsWith(".txt")) {
    outFilename = path.basename(outFilename, path.extname(outFilename)) + ".txt";
  }

  await statusMsg.delete().catch(() => {});
  await withRetry(() =>
    msg.reply({
      content: argLink ?? "from reply",
      files: [new AttachmentBuilder(buf, { name: outFilename })],
    })
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .help
// ─────────────────────────────────────────────────────────────────────────────

export async function helpCommand(msg: Message) {
  const isPriv = isOwnerOrCoOwner(msg.author.id);
  const lines = [
    "**Commands** — prefix: `.`",
    "",
    "`.l [link]` — deobfuscate / dump a Lua script (auto-injects Roblox environment)",
    "`.bf [link]` — beautify / reformat a Lua script",
    "`.darklua [link]` — apply Lua code transformations interactively (includes Roblox env injection)",
    "`.get [link]` — fetch a file from a URL and re-upload it",
    "`.info [@user]` — show your (or another user's) token balance & tier",
    "`.help` — show this message",
    "",
    "Attach a file, provide a URL, or reply to a message that contains one.",
  ];

  if (isPriv) {
    lines.push(
      "",
      "**Owner / Co-Owner commands:**",
      "`.setpremium @user` — upgrade a user to premium",
      "`.setfree @user` — downgrade a user to free",
      "`.addcoowner @user` — add a co-owner (owner only)",
      "`.removecoowner @user` — remove a co-owner (owner only)",
      "`.setlogchannel [#channel | channelId]` — set log channel (saves across bot restarts)",
      "`.bl add @user [reason]` — blacklist a user",
      "`.bl remove @user` — un-blacklist a user",
      "`.setrole @user <premium|free>` — set user role",
      "`.settoken @user <amount>` — set token balance",
      "`.stats` — show bot statistics and uptime",
    );
  }

  await msg.reply(lines.join("\n"));
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .info
// ─────────────────────────────────────────────────────────────────────────────

export async function infoCommand(msg: Message) {
  const target = msg.mentions.users.first() ?? msg.author;
  const user = getUser(target.id);
  const embed = new EmbedBuilder()
    .setColor(COLOR_INFO)
    .setTitle(`Info: ${target.tag}`)
    .addFields(
      { name: "Tier",      value: user.tier,                       inline: true },
      { name: "Tokens",    value: user.tokens === Infinity ? "∞" : String(user.tokens), inline: true },
      { name: "Commands",  value: String(user.commandsUsed),       inline: true },
      { name: "Blacklisted", value: user.blacklisted ? `Yes: ${user.blacklistReason}` : "No", inline: false },
    )
    .setFooter({ text: FILE_NAME });
  await msg.reply({ embeds: [embed] });
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .setpremium / .setfree  (owner + coowner only)
// ─────────────────────────────────────────────────────────────────────────────

export async function setPremiumCommand(msg: Message) {
  if (!isOwnerOrCoOwner(msg.author.id)) {
    return msg.reply("❌ Only owners and co-owners can use this command.");
  }
  const target = msg.mentions.users.first();
  if (!target) return msg.reply("❌ Mention a user: `.setpremium @user`");

  const user = getUser(target.id);
  if (isOwner(target.id)) return msg.reply("❌ Cannot change an owner's tier.");

  user.tier = "premium";
  user.tokens = PREMIUM_DEFAULT_TOKENS;
  saveUser(user);

  await sendLogEmbed(msg.client, "info", "setPremium",
    `${msg.author.tag} upgraded ${target.tag} to premium`,
    { by: msg.author.tag, target: target.tag, source: FILE_NAME });

  await msg.reply(`✅ **${target.tag}** is now **premium** (${PREMIUM_DEFAULT_TOKENS} tokens).`);
}

export async function setFreeCommand(msg: Message) {
  if (!isOwnerOrCoOwner(msg.author.id)) {
    return msg.reply("❌ Only owners and co-owners can use this command.");
  }
  const target = msg.mentions.users.first();
  if (!target) return msg.reply("❌ Mention a user: `.setfree @user`");

  const user = getUser(target.id);
  if (isOwner(target.id)) return msg.reply("❌ Cannot change an owner's tier.");

  user.tier = "free";
  user.tokens = FREE_DEFAULT_TOKENS;
  saveUser(user);

  await sendLogEmbed(msg.client, "info", "setFree",
    `${msg.author.tag} downgraded ${target.tag} to free`,
    { by: msg.author.tag, target: target.tag, source: FILE_NAME });

  await msg.reply(`✅ **${target.tag}** is now **free** (${FREE_DEFAULT_TOKENS} tokens).`);
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .addcoowner / .removecoowner  (owner only)
// ─────────────────────────────────────────────────────────────────────────────

export async function addCoOwnerCommand(msg: Message) {
  if (!isOwner(msg.author.id)) return msg.reply("❌ Only the owner can add co-owners.");
  const target = msg.mentions.users.first();
  if (!target) return msg.reply("❌ Mention a user: `.addcoowner @user`");
  if (isOwner(target.id)) return msg.reply("❌ That user is already an owner.");
  if (coOwnerIds.has(target.id)) return msg.reply(`❌ **${target.tag}** is already a co-owner.`);

  coOwnerIds.add(target.id);
  const user = getUser(target.id);
  user.tier = "coowner";
  user.tokens = Infinity;
  saveUser(user);

  await sendLogEmbed(msg.client, "info", "addCoOwner",
    `${msg.author.tag} added ${target.tag} as co-owner`,
    { by: msg.author.tag, target: target.tag, source: FILE_NAME });

  await msg.reply(`✅ **${target.tag}** is now a **co-owner**.`);
}

export async function removeCoOwnerCommand(msg: Message) {
  if (!isOwner(msg.author.id)) return msg.reply("❌ Only the owner can remove co-owners.");
  const target = msg.mentions.users.first();
  if (!target) return msg.reply("❌ Mention a user: `.removecoowner @user`");
  if (!coOwnerIds.has(target.id)) return msg.reply(`❌ **${target.tag}** is not a co-owner.`);

  coOwnerIds.delete(target.id);
  const user = getUser(target.id);
  user.tier = "free";
  user.tokens = FREE_DEFAULT_TOKENS;
  saveUser(user);

  await sendLogEmbed(msg.client, "info", "removeCoOwner",
    `${msg.author.tag} removed ${target.tag} from co-owner`,
    { by: msg.author.tag, target: target.tag, source: FILE_NAME });

  await msg.reply(`✅ **${target.tag}** has been removed from co-owners.`);
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .setlogchannel  (owner + coowner only) - SAVES TO ENV / FILE
// ─────────────────────────────────────────────────────────────────────────────

const LOG_CHANNEL_CONFIG_PATH = path.join(process.cwd(), "data", "logchannel.json");

function saveLogChannelConfig(channelId: string, guildId?: string) {
  try {
    const dir = path.dirname(LOG_CHANNEL_CONFIG_PATH);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const config = { channelId, guildId: guildId || null, updatedAt: Date.now() };
    fs.writeFileSync(LOG_CHANNEL_CONFIG_PATH, JSON.stringify(config, null, 2), "utf8");
  } catch (e) {
    logger.error({ e, source: FILE_NAME }, "Failed to save log channel config");
  }
}

function loadLogChannelConfig(): { channelId: string | null; guildId: string | null } {
  try {
    if (fs.existsSync(LOG_CHANNEL_CONFIG_PATH)) {
      const config = JSON.parse(fs.readFileSync(LOG_CHANNEL_CONFIG_PATH, "utf8"));
      return { channelId: config.channelId || null, guildId: config.guildId || null };
    }
  } catch (e) {
    logger.warn({ e, source: FILE_NAME }, "Failed to load log channel config");
  }
  return { channelId: process.env["BOT_LOG_CHANNEL_ID"] ?? null, guildId: null };
}

// Load saved log channel on module load
const savedLogConfig = loadLogChannelConfig();
logChannelId = savedLogConfig.channelId;
logChannelGuildId = savedLogConfig.guildId;

export async function setLogChannelCommand(msg: Message) {
  if (!isOwnerOrCoOwner(msg.author.id)) {
    return msg.reply("❌ Only owners and co-owners can use this command.");
  }

  const channelMention = msg.mentions.channels.first();
  const args = msg.content.split(/\s+/);
  let channelId: string | null = channelMention?.id ?? args[1] ?? null;
  let guildId: string | undefined = channelMention?.guildId ?? msg.guild?.id;

  if (!channelId) {
    // If no channel specified, show current config
    const current = getLogChannelId();
    if (current) {
      return msg.reply(`📋 Current log channel: <#${current}> in guild ${logChannelGuildId || "unknown"}\nUse \`.setlogchannel #channel\` to change, or \`.setlogchannel none\` to disable.`);
    } else {
      return msg.reply(`📋 No log channel configured.\nUse \`.setlogchannel #channel\` to set one.`);
    }
  }

  if (channelId.toLowerCase() === "none" || channelId.toLowerCase() === "disable") {
    // Disable logging
    setLogChannel("", undefined);
    saveLogChannelConfig("", undefined);
    await sendLogEmbed(msg.client, "info", "setLogChannel",
      `${msg.author.tag} disabled log channel`,
      { by: msg.author.tag, source: FILE_NAME });
    return msg.reply("✅ Log channel has been disabled.");
  }

  // Verify channel exists and bot can access it
  try {
    const channel = await msg.client.channels.fetch(channelId);
    if (!channel || !channel.isTextBased()) {
      return msg.reply("❌ Invalid channel ID or bot cannot access that channel.");
    }
    const textChannel = channel as TextChannel;
    // Test send a message
    await textChannel.send("✅ Log channel configured successfully! This channel will receive bot logs.");
  } catch (err) {
    logger.warn({ err, source: FILE_NAME }, "Failed to verify log channel");
    return msg.reply("❌ Cannot access that channel. Make sure the channel ID is correct and the bot has permission to send messages there.");
  }

  setLogChannel(channelId, guildId);
  saveLogChannelConfig(channelId, guildId);

  await sendLogEmbed(msg.client, "info", "setLogChannel",
    `${msg.author.tag} set log channel to <#${channelId}> (${channelId}) in guild ${guildId || "unknown"}`,
    { by: msg.author.tag, channelId, source: FILE_NAME });

  await msg.reply(`✅ Log channel set to <#${channelId}>. Errors, warnings, and info will be sent there.`);
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .bl  (blacklist management – owner + coowner)
// ─────────────────────────────────────────────────────────────────────────────

export async function blacklistCommand(msg: Message) {
  if (!isOwnerOrCoOwner(msg.author.id)) return msg.reply("❌ No permission.");

  const args = msg.content.split(/\s+/);
  const sub = args[1]?.toLowerCase();
  const target = msg.mentions.users.first();

  if (!sub || !target) return msg.reply("Usage: `.bl add @user [reason]` / `.bl remove @user`");

  if (sub === "add") {
    const reason = args.slice(3).join(" ") || "No reason provided";
    const user = getUser(target.id);
    if (isOwner(target.id)) return msg.reply("❌ Cannot blacklist an owner.");
    user.blacklisted = true;
    user.blacklistReason = reason;
    user.blacklistExpiry = null;
    saveUser(user);

    await sendLogEmbed(msg.client, "warn", "Blacklist add",
      `${msg.author.tag} blacklisted ${target.tag}: ${reason}`,
      { source: FILE_NAME });
    return msg.reply(`🚫 **${target.tag}** has been blacklisted. Reason: ${reason}`);
  }

  if (sub === "remove") {
    const user = getUser(target.id);
    user.blacklisted = false;
    user.blacklistReason = "";
    user.blacklistExpiry = null;
    saveUser(user);

    await sendLogEmbed(msg.client, "info", "Blacklist remove",
      `${msg.author.tag} removed blacklist from ${target.tag}`,
      { source: FILE_NAME });
    return msg.reply(`✅ **${target.tag}** has been un-blacklisted.`);
  }

  return msg.reply("❌ Unknown sub-command. Use `add` or `remove`.");
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .setrole  (owner + coowner)
// ─────────────────────────────────────────────────────────────────────────────

export async function setRoleCommand(msg: Message) {
  if (!isOwnerOrCoOwner(msg.author.id)) return msg.reply("❌ No permission.");

  const args = msg.content.split(/\s+/);
  const target = msg.mentions.users.first();
  const role = args[2]?.toLowerCase() as UserTier;

  if (!target || !["premium", "free"].includes(role)) {
    return msg.reply("Usage: `.setrole @user <premium|free>`");
  }
  if (isOwner(target.id)) return msg.reply("❌ Cannot change an owner's role.");

  const user = getUser(target.id);
  user.tier = role;
  user.tokens = role === "premium" ? PREMIUM_DEFAULT_TOKENS : FREE_DEFAULT_TOKENS;
  saveUser(user);

  await sendLogEmbed(msg.client, "info", "setRole",
    `${msg.author.tag} set ${target.tag} role to ${role}`,
    { source: FILE_NAME });
  await msg.reply(`✅ **${target.tag}** role set to **${role}**.`);
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: .settoken  (owner + coowner)
// ─────────────────────────────────────────────────────────────────────────────

export async function setTokenCommand(msg: Message) {
  if (!isOwnerOrCoOwner(msg.author.id)) return msg.reply("❌ No permission.");

  const args = msg.content.split(/\s+/);
  const target = msg.mentions.users.first();
  const amount = parseInt(args[2] ?? "");

  if (!target || isNaN(amount)) return msg.reply("Usage: `.settoken @user <amount>`");

  const user = getUser(target.id);
  if (user.tier === "owner" || user.tier === "coowner") {
    return msg.reply("❌ Cannot modify tokens for owners or co-owners (they have unlimited tokens).");
  }
  user.tokens = Math.max(0, amount);
  saveUser(user);

  await sendLogEmbed(msg.client, "info", "setToken",
    `${msg.author.tag} set ${target.tag} tokens to ${amount}`,
    { source: FILE_NAME });
  await msg.reply(`✅ **${target.tag}** tokens set to **${amount}**.`);
}

// ─────────────────────────────────────────────────────────────────────────────
// FIX #19: COMMAND: .stats  (admin statistics + uptime)
// ─────────────────────────────────────────────────────────────────────────────

export async function statsCommand(msg: Message) {
  if (!isOwnerOrCoOwner(msg.author.id)) {
    return msg.reply("❌ Permission denied.");
  }

  // FIX 4: Rate limit .stats 15 detik agar tidak bisa di-spam
  const remaining = checkRateLimit(msg.author.id, ".stats");
  if (remaining > 0) {
    return msg.reply(`⏳ Tunggu **${remaining.toFixed(1)}s** sebelum cek stats lagi.`);
  }

  const totalUsers    = userDb.size;
  const premiumCount  = [...userDb.values()].filter((u) => u.tier === "premium").length;
  const coownerCount  = [...userDb.values()].filter((u) => u.tier === "coowner").length;
  const blacklisted   = [...userDb.values()].filter((u) => u.blacklisted).length;
  const uptime        = process.uptime();
  const uptimeStr     = `${Math.floor(uptime / 3600)}h ${Math.floor((uptime % 3600) / 60)}m ${Math.floor(uptime % 60)}s`;
  const memMB         = (process.memoryUsage().heapUsed / 1024 / 1024).toFixed(1);
  const queueDepth    = dumpSemaphore.atCapacity ? "🔴 penuh (3/3)" : "🟢 tersedia";

  const embed = new EmbedBuilder()
    .setTitle("📊 Bot Statistics")
    .setColor(COLOR_INFO)
    .addFields(
      { name: "⏱ Uptime",        value: uptimeStr,             inline: true },
      { name: "👥 Total Users",   value: String(totalUsers),    inline: true },
      { name: "⭐ Premium",       value: String(premiumCount),  inline: true },
      { name: "🔑 Co-Owners",     value: String(coownerCount),  inline: true },
      { name: "🚫 Blacklisted",   value: String(blacklisted),   inline: true },
      { name: "🖥 Memory",        value: `${memMB} MB`,         inline: true },
      { name: "🔧 Lua Interp",    value: _luaInterp ?? "unknown", inline: true },
      { name: "⚙ Dump Queue",    value: queueDepth,            inline: true },
      { name: "📝 Log Channel",   value: logChannelId ? `<#${logChannelId}>` : "❌ Not set", inline: false },
    )
    .setFooter({ text: FILE_NAME })
    .setTimestamp();

  await msg.reply({ embeds: [embed] });
}

export { userDb as users, coOwnerIds };

export function hasEnoughTokens(userId: string): boolean {
  return hasTokens(userId);
}

export function spendToken(userId: string) {
  deductToken(userId);
  const user = getUser(userId);
  user.commandsUsed += 1;
  saveUser(user);
}