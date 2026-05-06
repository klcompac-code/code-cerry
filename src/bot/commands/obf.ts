/**
 * obf.ts — Command .obf
 *
 * Menggunakan Prometheus Obfuscator (Lua) untuk obfuskasi kode.
 * Cara kerja:
 *   1. Tulis kode user ke temp file
 *   2. Spawn: lua <PROMETHEUS_PATH> --preset <preset> <input> --out <output>
 *   3. Baca output → kirim ke Discord
 *   4. Cleanup temp files
 *
 * Setup di server:
 *   - Letakkan folder Prometheus di path yang ditentukan PROMETHEUS_PATH (env var)
 *   - Pastikan `lua` atau `lua5.1` tersedia di PATH
 *   - Contoh: PROMETHEUS_PATH=/home/user/prometheus/prometheus-main.lua
 */

import { Message, AttachmentBuilder } from "discord.js";
import { spawn } from "child_process";
import { randomBytes } from "crypto";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import { checkAntiVuln, formatBlockedMessage } from "../anti-vuln";
import { logger } from "../../lib/logger";

// ─────────────────────────────────────────────────────────────────────────────
// KONFIGURASI
// ─────────────────────────────────────────────────────────────────────────────

const FILE_NAME = "obf.ts";

// Path ke prometheus-main.lua — bisa di-override via env var
const PROMETHEUS_PATH = process.env["PROMETHEUS_PATH"]
  ?? path.join(__dirname, "..", "prometheus", "prometheus-main.lua");

// Interpreter Lua yang akan dicoba
const LUA_INTERPRETERS = ["lua5.1", "lua", "lua5.3", "lua5.4", "luajit"];

// Timeout untuk proses obfuskasi (ms)
const OBF_TIMEOUT_MS = 60_000; // 60 detik

// Max ukuran file input
const MAX_INPUT_BYTES = 5 * 1024 * 1024; // 5 MB

// Preset yang tersedia di Prometheus (dari presets.lua)
const VALID_PRESETS = [
  "Minify",
  "Weak",
  "Medium",
  "Strong",
  "Maximum",
  "Supreme",
  "Vmify",
  "RobloxExecutor",
] as const;

type PrometheusPreset = (typeof VALID_PRESETS)[number];

// Preset default jika user tidak spesifikasi
const DEFAULT_PRESET: PrometheusPreset = "Medium";

// ─────────────────────────────────────────────────────────────────────────────
// LUA INTERPRETER DETECTION
// ─────────────────────────────────────────────────────────────────────────────

let _luaInterp: string | null = null;

async function findLua(): Promise<string | null> {
  if (_luaInterp) return _luaInterp;

  for (const interp of LUA_INTERPRETERS) {
    const result = await runProcess(interp, ["-e", "print('ok')"], OBF_TIMEOUT_MS);
    if (result.code === 0 && result.stdout.trim() === "ok") {
      _luaInterp = interp;
      logger.info({ interp, source: FILE_NAME }, "Lua interpreter found for Prometheus");
      return interp;
    }
  }

  logger.warn({ source: FILE_NAME }, "Tidak ada Lua interpreter yang ditemukan untuk Prometheus");
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

function runProcess(
  cmd: string,
  args: string[],
  timeoutMs: number
): Promise<ProcessResult> {
  return new Promise((resolve) => {
    let proc: ReturnType<typeof spawn>;
    try {
      proc = spawn(cmd, args, { shell: false });
    } catch {
      return resolve({ code: -1, stdout: "", stderr: "spawn error" });
    }

    const chunks: Buffer[] = [];
    const errChunks: Buffer[] = [];

    // Batasi output 10MB agar tidak OOM
    const MAX_OUT = 10 * 1024 * 1024;
    let totalBytes = 0;
    let killed = false;

    proc.stdout.on("data", (d: Buffer) => {
      totalBytes += d.length;
      if (totalBytes > MAX_OUT) {
        if (!killed) { killed = true; proc.kill("SIGKILL"); }
        return;
      }
      chunks.push(d);
    });
    proc.stderr.on("data", (d: Buffer) => errChunks.push(d));

    const timer = setTimeout(() => {
      proc.kill("SIGKILL");
      resolve({ code: -1, stdout: "", stderr: "timeout" });
    }, timeoutMs);

    proc.on("close", (code) => {
      clearTimeout(timer);
      resolve({
        code: code ?? -1,
        stdout: Buffer.concat(chunks).toString("utf8"),
        stderr: Buffer.concat(errChunks).toString("utf8"),
      });
    });

    proc.on("error", () => {
      clearTimeout(timer);
      resolve({ code: -1, stdout: "", stderr: "spawn error" });
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PROMETHEUS RUNNER
// ─────────────────────────────────────────────────────────────────────────────

interface ObfResult {
  output: string | null;
  error: string | null;
}

async function runPrometheus(
  code: string,
  preset: PrometheusPreset
): Promise<ObfResult> {
  // Validasi PROMETHEUS_PATH agar tidak bisa di-inject via env
  const safePath = path.resolve(PROMETHEUS_PATH);
  if (!fs.existsSync(safePath)) {
    return {
      output: null,
      error: `Prometheus tidak ditemukan di: ${safePath}\nSet env var PROMETHEUS_PATH ke path prometheus-main.lua`,
    };
  }

  const interp = await findLua();
  if (!interp) {
    return {
      output: null,
      error: "Tidak ada Lua interpreter yang tersedia. Install lua5.1 di server.",
    };
  }

  // Temp files dengan random suffix
  const uid = randomBytes(16).toString("hex");
  const inputFile  = path.join(os.tmpdir(), `prom_in_${uid}.lua`);
  const outputFile = path.join(os.tmpdir(), `prom_out_${uid}.lua`);

  try {
    fs.writeFileSync(inputFile, code, "utf8");

    // Panggil: lua prometheus-main.lua --preset <preset> <input> --out <output>
    const args = [
      safePath,
      "--preset", preset,
      inputFile,
      "--out", outputFile,
    ];

    logger.info({ preset, inputFile, source: FILE_NAME }, "Running Prometheus");
    const result = await runProcess(interp, args, OBF_TIMEOUT_MS);

    if (result.stderr.includes("timeout")) {
      return { output: null, error: "⏱ Obfuskasi timeout (>60s). Coba kode yang lebih kecil." };
    }

    // Cek apakah output file berhasil dibuat
    if (fs.existsSync(outputFile)) {
      const obfuscated = fs.readFileSync(outputFile, "utf8");
      return { output: obfuscated, error: null };
    }

    // Ambil baris error terakhir dari stderr/stdout
    const errLines = (result.stderr || result.stdout).trim().split("\n");
    const lastErr = errLines.filter(Boolean).pop() ?? "Output tidak dihasilkan";
    return { output: null, error: `❌ Prometheus error: ${sanitizeError(lastErr)}` };

  } catch (e: any) {
    return { output: null, error: `❌ Internal error: ${e?.message ?? String(e)}` };
  } finally {
    // Cleanup temp files
    for (const f of [inputFile, outputFile]) {
      try { if (fs.existsSync(f)) fs.unlinkSync(f); } catch {}
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Sanitize error — hapus path absolut server dari pesan error
// ─────────────────────────────────────────────────────────────────────────────

function sanitizeError(err: string): string {
  return err
    .replace(/\/[a-zA-Z0-9_\-./]+\.(lua|ts|js|py)/g, "<path>")
    .replace(/\/home\/[^\s/]+/g, "<home>")
    .replace(/\/tmp\/[^\s/]+/g, "<tmp>")
    .replace(/\/root\/[^\s/]*/g, "<root>");
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Ekstrak kode dari pesan
// ─────────────────────────────────────────────────────────────────────────────

function extractCode(msg: Message): string {
  const content = msg.content.replace(/^\.obf\s*/i, "").trim();

  // Codeblock ```lua ... ``` atau ``` ... ```
  const cbMatch = content.match(/^```(?:lua|luau)?\n?([\s\S]*?)\n?```$/);
  if (cbMatch) return cbMatch[1].trim();

  return content;
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Parse preset dari argumen
// Contoh: ".obf Strong" → preset = "Strong"
// ─────────────────────────────────────────────────────────────────────────────

function parsePreset(msg: Message): { preset: PrometheusPreset; rawCode: string } {
  // Format: .obf [preset] <kode atau kosong>
  const parts = msg.content.trim().split(/\s+/);
  // parts[0] = ".obf", parts[1] mungkin preset
  const maybePreset = parts[1];
  const presetMatch = VALID_PRESETS.find(
    (p) => p.toLowerCase() === maybePreset?.toLowerCase()
  );

  if (presetMatch) {
    // Ada preset di argumen — kode mulai dari parts[2]
    const afterPreset = parts.slice(2).join(" ").trim();
    return { preset: presetMatch, rawCode: afterPreset };
  }

  // Tidak ada preset — kode mulai dari parts[1]
  return { preset: DEFAULT_PRESET, rawCode: parts.slice(1).join(" ").trim() };
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN COMMAND
// ─────────────────────────────────────────────────────────────────────────────

export async function obfCommand(msg: Message) {
  let rawCode = "";
  let preset: PrometheusPreset = DEFAULT_PRESET;

  // ── 1. Attachment ────────────────────────────────────────────────────────
  if (msg.attachments.size > 0) {
    const att = msg.attachments.first()!;

    if (!att.name?.match(/\.(lua|luau|txt)$/i)) {
      await msg.reply("❌ Upload file `.lua`, `.luau`, atau `.txt` saja.");
      return;
    }

    if ((att.size ?? 0) > MAX_INPUT_BYTES) {
      await msg.reply("❌ File terlalu besar (max 5MB).");
      return;
    }

    try {
      const res = await fetch(att.url);
      rawCode = await res.text();
    } catch {
      await msg.reply("❌ Gagal download attachment.");
      return;
    }

    // Cek preset dari argumen meski input dari file
    const parsed = parsePreset(msg);
    preset = parsed.preset;

  // ── 2. Reply ke pesan yang berisi kode ──────────────────────────────────
  } else if (msg.reference?.messageId) {
    const ref = await msg.channel.messages.fetch(msg.reference.messageId).catch(() => null);
    if (!ref) {
      await msg.reply("❌ Tidak bisa mengambil pesan yang di-reply.");
      return;
    }

    // Coba ambil dari attachment di pesan yang di-reply
    if (ref.attachments.size > 0) {
      const att = ref.attachments.first()!;
      if (att.name?.match(/\.(lua|luau|txt)$/i)) {
        try {
          const res = await fetch(att.url);
          rawCode = await res.text();
        } catch {}
      }
    }

    // Fallback ke content teks
    if (!rawCode) rawCode = ref.content;

    const parsed = parsePreset(msg);
    preset = parsed.preset;

  // ── 3. Inline code / codeblock ───────────────────────────────────────────
  } else {
    const parsed = parsePreset(msg);
    preset = parsed.preset;

    // extractCode dari msg content (tanpa prefix .obf [preset])
    const stripped = msg.content.replace(/^\.obf\s*/i, "").replace(new RegExp(`^${preset}\\s*`, "i"), "").trim();
    const cbMatch = stripped.match(/^```(?:lua|luau)?\n?([\s\S]*?)\n?```$/);
    rawCode = cbMatch ? cbMatch[1].trim() : stripped;
  }

  // ── Validasi kode tidak kosong ───────────────────────────────────────────
  if (!rawCode.trim()) {
    const presetList = VALID_PRESETS.join(", ");
    await msg.reply(
      `**Cara penggunaan:**\n` +
      `\`.obf [preset] <kode lua>\`\n` +
      `\`.obf [preset]\` + upload file .lua\n` +
      `\`.obf [preset]\` + reply ke pesan berisi kode\n\n` +
      `**Preset tersedia:** ${presetList}\n` +
      `**Default preset:** ${DEFAULT_PRESET}`
    );
    return;
  }

  // ── Anti-vuln check ──────────────────────────────────────────────────────
  const vulv = checkAntiVuln(rawCode);
  if (vulv.blocked) {
    await msg.reply(formatBlockedMessage(vulv));
    return;
  }

  // ── Status message ───────────────────────────────────────────────────────
  const statusMsg = await msg.reply(`⏳ Obfuscating dengan preset **${preset}**...`).catch(() => null);

  // ── Jalankan Prometheus ──────────────────────────────────────────────────
  const { output, error } = await runPrometheus(rawCode, preset);

  // Hapus status message
  if (statusMsg) await statusMsg.delete().catch(() => {});

  if (error || !output) {
    await msg.reply(error ?? "❌ Obfuskasi gagal tanpa alasan yang jelas.");
    return;
  }

  // ── Kirim hasil ───────────────────────────────────────────────────────────
  const randSuffix = randomBytes(3).toString("hex").slice(0, 5);

  if (output.length > 1900) {
    const buf = Buffer.from(output, "utf-8");
    const att = new AttachmentBuilder(buf, { name: `obfuscated_${randSuffix}.lua` });
    await msg.reply({
      content: `✅ Obfuscated dengan **${preset}** (dikirim sebagai file):`,
      files: [att],
    });
  } else {
    await msg.reply(
      `✅ Obfuscated dengan **${preset}**:\n\`\`\`lua\n${output}\n\`\`\``
    );
  }
}
