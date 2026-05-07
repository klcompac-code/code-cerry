import { Message } from "discord.js";
import { getUser, saveUser } from "../db";

const OWNER_IDS: string[] = (process.env["BOT_OWNER_IDS"] ?? "").split(",").filter(Boolean);

function parseDuration(dur: string): number | null {
  if (dur === "-" || dur === "perm") return null;
  const match = dur.match(/^(\d+)(h|d|w)$/i);
  if (!match) return null;
  const val = parseInt(match[1], 10);
  const unit = match[2].toLowerCase();
  const multipliers: Record<string, number> = { h: 3600000, d: 86400000, w: 604800000 };
  return Date.now() + val * multipliers[unit];
}

export async function blacklistCommand(msg: Message) {
  if (OWNER_IDS.length > 0 && !OWNER_IDS.includes(msg.author.id)) {
    await msg.reply("You do not have permission to use this command.");
    return;
  }

  const parts = msg.content.split(/\s+/);
  const userId = parts[1];
  const duration = parts[2] ?? "-";
  const reason = parts.slice(3).join(" ") || "-";

  if (!userId || !/^\d{17,20}$/.test(userId)) {
    await msg.reply("Usage: `.bl <userId> <duration> <reason>`\nDuration: `1h`, `1d`, `7d`, `perm`, or `-` for permanent.\nReason: text or `-` for none.");
    return;
  }

  const expiry = parseDuration(duration);
  const user = getUser(userId);
  user.blacklisted = true;
  user.blacklistReason = reason === "-" ? "" : reason;
  user.blacklistExpiry = expiry;
  saveUser(user);

  const expiryStr = expiry ? new Date(expiry).toUTCString() : "Permanent";

  const embed = {
    color: 0xe74c3c,
    title: "🚫 User Blacklisted",
    fields: [
      { name: "User ID", value: userId, inline: true },
      { name: "Duration", value: expiryStr, inline: true },
      { name: "Reason", value: reason === "-" ? "No reason given" : reason, inline: false },
    ],
    footer: { text: `Blacklisted by ${msg.author.username}` },
  };

  await msg.reply({ embeds: [embed] });
}
