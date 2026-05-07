/**
 * Anti-Vuln Module
 * Hanya memblokir library berbahaya: os dan io
 * Library Roblox seperti load, loadstring, require, dll TIDAK diblokir
 */

export interface VulvCheckResult {
  blocked: boolean;
  match: string | null;
  library: string | null;
}

// Pola berbahaya — hanya os.* dan io.*
const BLOCKED_PATTERNS: Array<{ pattern: RegExp; library: string }> = [
  // os library
  { pattern: /\bos\s*\.\s*exit\b/,    library: "os" },
  { pattern: /\bos\s*\.\s*execute\b/, library: "os" },
  { pattern: /\bos\s*\.\s*remove\b/,  library: "os" },
  { pattern: /\bos\s*\.\s*rename\b/,  library: "os" },
  { pattern: /\bos\s*\.\s*tmpname\b/, library: "os" },
  { pattern: /\bos\s*\.\s*getenv\b/,  library: "os" },
  { pattern: /\bos\s*\.\s*clock\b/,   library: "os" },
  { pattern: /\bos\s*\.\s*time\b/,    library: "os" },
  { pattern: /\bos\s*\.\s*date\b/,    library: "os" },
  { pattern: /\bos\s*\.\s*difftime\b/,library: "os" },

  // io library
  { pattern: /\bio\s*\.\s*open\b/,    library: "io" },
  { pattern: /\bio\s*\.\s*close\b/,   library: "io" },
  { pattern: /\bio\s*\.\s*read\b/,    library: "io" },
  { pattern: /\bio\s*\.\s*write\b/,   library: "io" },
  { pattern: /\bio\s*\.\s*lines\b/,   library: "io" },
  { pattern: /\bio\s*\.\s*popen\b/,   library: "io" },
  { pattern: /\bio\s*\.\s*tmpfile\b/, library: "io" },
  { pattern: /\bio\s*\.\s*input\b/,   library: "io" },
  { pattern: /\bio\s*\.\s*output\b/,  library: "io" },
];

/**
 * Cek apakah kode mengandung fungsi yang diblokir (os/io)
 * Mengembalikan info match pertama yang ditemukan, atau blocked=false jika aman
 */
export function checkAntiVuln(code: string): VulvCheckResult {
  for (const { pattern, library } of BLOCKED_PATTERNS) {
    const m = code.match(pattern);
    if (m) {
      return { blocked: true, match: m[0], library };
    }
  }
  return { blocked: false, match: null, library: null };
}

/**
 * Format pesan error untuk Discord ketika kode diblokir
 */
export function formatBlockedMessage(result: VulvCheckResult): string {
  return (
    `🚫 Kode mengandung fungsi yang diblokir: \`${result.match}\`\n` +
    `Library \`${result.library}\` tidak diizinkan karena dapat membahayakan server.`
  );
}
