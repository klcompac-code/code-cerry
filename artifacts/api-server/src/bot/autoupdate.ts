import { Client } from "discord.js";
import { execSync } from "child_process";
import { logger } from "../lib/logger";
import { getOwnerIds, config } from "./config";

let pendingUpdate = false;
let updateTimer: ReturnType<typeof setInterval> | null = null;

function setupGitRemote(): boolean {
  const pat = process.env["GITHUB_PAT"];
  const repo = process.env["GITHUB_REPO"];
  if (!pat || !repo) {
    logger.warn("GITHUB_PAT or GITHUB_REPO not set — auto-update disabled");
    return false;
  }
  try {
    execSync(`git remote set-url origin https://${pat}@github.com/${repo}.git`, {
      cwd: process.cwd(),
      stdio: "pipe",
    });
    return true;
  } catch (err) {
    logger.error({ err }, "Failed to set git remote URL");
    return false;
  }
}

function getNewCommits(): string {
  try {
    execSync("git fetch origin main --quiet", { cwd: process.cwd(), stdio: "pipe" });
    const log = execSync("git log HEAD..origin/main --oneline", {
      cwd: process.cwd(),
      stdio: "pipe",
    }).toString().trim();
    return log;
  } catch (err) {
    logger.error({ err }, "git fetch/log failed");
    return "";
  }
}

async function notifyPrivilegedUsers(client: Client, commits: string): Promise<void> {
  const ids = [...getOwnerIds(), ...config.coOwnerIds];
  const unique = [...new Set(ids)];

  const embed = {
    color: 0x3498db,
    title: "📦 Update Tersedia di GitHub",
    description:
      `Ada commit baru di branch **main**:\n\`\`\`\n${commits.slice(0, 900)}\n\`\`\`\n` +
      `Ketik \`.confirm\` untuk mulai update & restart bot.\n` +
      `Ketik \`.deny\` untuk skip update ini.`,
    footer: { text: "Auto-Update System" },
    timestamp: new Date().toISOString(),
  };

  for (const id of unique) {
    try {
      const user = await client.users.fetch(id);
      await user.send({ embeds: [embed] });
      logger.info({ userId: id }, "Sent update confirmation DM");
    } catch (err) {
      logger.warn({ err, userId: id }, "Failed to DM user for update confirmation");
    }
  }
}

export async function checkForUpdates(client: Client): Promise<void> {
  if (pendingUpdate) return;

  const ok = setupGitRemote();
  if (!ok) return;

  const commits = getNewCommits();
  if (!commits) {
    logger.info("Auto-update: no new commits");
    return;
  }

  logger.info({ commits }, "New commits found — notifying owners");
  pendingUpdate = true;
  await notifyPrivilegedUsers(client, commits);
}

export async function confirmUpdate(client: Client, userId: string): Promise<string> {
  if (!pendingUpdate) return "⚠️ Tidak ada update yang menunggu konfirmasi.";

  pendingUpdate = false;

  const user = await client.users.fetch(userId);
  await user.send("✅ Update dikonfirmasi! Memulai proses update...\n> Bot akan restart sebentar.");

  logger.info({ userId }, "Update confirmed — pulling and rebuilding");

  setTimeout(() => {
    try {
      execSync("git pull origin main", { cwd: process.cwd(), stdio: "inherit" });
      logger.info("git pull done — rebuilding...");

      const distPath = process.env["BUILD_CMD_DIR"] ?? "artifacts/api-server";
      execSync(`cd ${distPath} && pnpm run build`, {
        cwd: process.cwd(),
        stdio: "inherit",
      });

      logger.info("Build done — restarting process");
      process.exit(0);
    } catch (err) {
      logger.error({ err }, "Update failed");
      client.users.fetch(userId).then((u) =>
        u.send("❌ Update gagal. Cek log server untuk detail.").catch(() => {})
      );
    }
  }, 1500);

  return "✅ Memulai update...";
}

export function denyUpdate(): string {
  if (!pendingUpdate) return "⚠️ Tidak ada update yang menunggu konfirmasi.";
  pendingUpdate = false;
  logger.info("Update denied by privileged user");
  return "❌ Update di-skip. Bot tetap berjalan dengan versi saat ini.";
}

export function hasPendingUpdate(): boolean {
  return pendingUpdate;
}

export function startAutoUpdate(client: Client): void {
  if (!config.autoUpdateEnabled) {
    logger.info("Auto-update disabled in config");
    return;
  }

  const ok = setupGitRemote();
  if (!ok) return;

  logger.info({ intervalMs: config.autoUpdateIntervalMs }, "Auto-update scheduler started");

  updateTimer = setInterval(() => {
    checkForUpdates(client).catch((err) => logger.error({ err }, "Auto-update check error"));
  }, config.autoUpdateIntervalMs);

  checkForUpdates(client).catch((err) => logger.error({ err }, "Initial update check error"));
}

export function stopAutoUpdate(): void {
  if (updateTimer) {
    clearInterval(updateTimer);
    updateTimer = null;
  }
}
