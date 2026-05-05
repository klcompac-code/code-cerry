import { Message } from "discord.js";
import { isBlacklisted, hasTokens, deductToken, incrementCommandsUsed } from "./db";
import { helpCommand } from "./commands/help";
import { luaCommand } from "./commands/lua";
import { detectCommand } from "./commands/detect";
import { obfCommand } from "./commands/obf";
import { infoCommand } from "./commands/info";
import { giftCommand } from "./commands/gift";
import { blacklistCommand } from "./commands/blacklist";
import { setRoleCommand } from "./commands/setrole";
import { setTokenCommand } from "./commands/settoken";
import { configCommand } from "./commands/configcmd";
import { setConfigCommand } from "./commands/setconfig";
import { logger } from "../lib/logger";
import { config } from "./config";

// ── Rate limiting ──────────────────────────────────────────────────────────────
const userCooldowns = new Map<string, number>();
const RATE_LIMIT_SECONDS = 5;

function checkRateLimit(userId: string): number {
  const now = Date.now();
  const lastUse = userCooldowns.get(userId) ?? 0;
  const elapsed = (now - lastUse) / 1000;
  if (elapsed < RATE_LIMIT_SECONDS) return RATE_LIMIT_SECONDS - elapsed;
  userCooldowns.set(userId, now);
  return 0;
}

// ── URL validation (SSRF protection) ──────────────────────────────────────────
export function isValidUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    if (!["http:", "https:"].includes(parsed.protocol)) return false;
    const hostname = parsed.hostname ?? "";
    const blocked = [
      /^localhost$/i,
      /\.local$/i,
      /\.internal$/i,
      /^127\./,
      /^192\.168\./,
      /^10\./,
      /^172\.(1[6-9]|2\d|3[01])\./,
    ];
    return !blocked.some((p) => p.test(hostname));
  } catch {
    return false;
  }
}

// ── Code extraction helpers ────────────────────────────────────────────────────
export async function extractCodeFromMessage(msg: Message): Promise<string | null> {
  const codeBlockMatch = msg.content.match(/```(?:lua)?\n?([\s\S]*?)\n?```/);
  if (codeBlockMatch) return codeBlockMatch[1];

  if (msg.attachments.size > 0) {
    const attachment = msg.attachments.first()!;
    if (attachment.name?.endsWith(".lua")) {
      try {
        const response = await fetch(attachment.url);
        return await response.text();
      } catch (error) {
        logger.error({ error }, "Failed to fetch attachment");
        return null;
      }
    }
  }

  if (msg.reference) {
    try {
      const repliedTo = await msg.channel.messages.fetch(msg.reference.messageId!);
      return extractCodeFromMessage(repliedTo);
    } catch (error) {
      logger.error({ error }, "Failed to fetch replied message");
      return null;
    }
  }

  return null;
}

// ── Response formatter ─────────────────────────────────────────────────────────
export async function sendFormattedResponse(
  msg: Message,
  content: string,
  title = "Result"
): Promise<void> {
  if (content.length <= 1980) {
    await msg.reply({
      content: `\`\`\`lua\n${content}\n\`\`\``,
      allowedMentions: { repliedUser: false },
    });
  } else {
    await msg.reply({
      files: [
        {
          attachment: Buffer.from(content, "utf-8"),
          name: `${title.toLowerCase().replace(/\s+/g, "_")}.lua`,
        },
      ],
      allowedMentions: { repliedUser: false },
    });
  }
}

// ── Command set that costs tokens ──────────────────────────────────────────────
const TOKEN_COMMANDS = new Set([".l", ".detect", ".obf", ".gift"]);

// ── Main message handler ───────────────────────────────────────────────────────
export async function handleMessage(msg: Message) {
  if (msg.author.bot) return;
  if (!msg.content.startsWith(".")) return;

  const cmd = msg.content.split(/\s+/)[0].toLowerCase();

  // Rate limit for token-consuming commands
  const cooldown = checkRateLimit(msg.author.id);
  if (cooldown > 0 && TOKEN_COMMANDS.has(cmd)) {
    await msg.reply(`⏳ Please wait **${cooldown.toFixed(1)}s** before using this command again.`);
    return;
  }

  const isDm = !msg.guild;
  if (isDm && !config.allowDmCommands) {
    await msg.reply("❌ Commands can only be used inside a server, not in DMs.");
    return;
  }

  if (isBlacklisted(msg.author.id) && cmd !== ".info") {
    await msg.reply("🚫 You are blacklisted and cannot use this bot.");
    return;
  }

  if (TOKEN_COMMANDS.has(cmd) && !hasTokens(msg.author.id)) {
    await msg.reply(
      "❌ You don't have enough tokens. Tokens restore **+1 every hour**. Use `.info` to check your balance."
    );
    return;
  }

  try {
    switch (cmd) {
      case ".help":
        await helpCommand(msg);
        break;
      case ".l":
        await luaCommand(msg);
        deductToken(msg.author.id);
        incrementCommandsUsed(msg.author.id);
        break;
      case ".detect":
        await detectCommand(msg);
        deductToken(msg.author.id);
        incrementCommandsUsed(msg.author.id);
        break;
      case ".obf":
        await obfCommand(msg);
        deductToken(msg.author.id);
        incrementCommandsUsed(msg.author.id);
        break;
      case ".info":
        await infoCommand(msg);
        break;
      case ".gift":
        await giftCommand(msg);
        deductToken(msg.author.id);
        incrementCommandsUsed(msg.author.id);
        break;
      case ".bl":
        await blacklistCommand(msg);
        break;
      case ".setrole":
        await setRoleCommand(msg);
        break;
      case ".settoken":
        await setTokenCommand(msg);
        break;
      case ".config":
        await configCommand(msg);
        break;
      case ".setconfig":
        await setConfigCommand(msg);
        break;
      default:
        break;
    }
  } catch (err) {
    logger.error({ err, cmd }, "Error handling command");
    try {
      await msg.reply("❌ An error occurred while processing your command.");
    } catch {}
  }
}
