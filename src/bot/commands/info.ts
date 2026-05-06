import { Message } from "discord.js";
import { getUser, isBlacklisted, UserRole } from "../db";

const roleLabels: Record<UserRole, string> = {
  owner: "👑 Owner",
  premium: "💎 Premium",
  free: "🆓 Free",
};

const roleColors: Record<UserRole, number> = {
  owner: 0xf1c40f,
  premium: 0x9b59b6,
  free: 0x3498db,
};

export async function infoCommand(msg: Message) {
  const mentioned = msg.mentions.users.first();
  const target = mentioned ?? msg.author;

  const record = getUser(target.id);
  const blStatus = isBlacklisted(target.id);

  let blField = "No";
  if (blStatus) {
    blField = `Yes — ${record.blacklistReason || "No reason given"}`;
    if (record.blacklistExpiry) {
      const exp = new Date(record.blacklistExpiry).toUTCString();
      blField += `\nExpires: ${exp}`;
    }
  }

  const tokenDisplay = record.role === "owner" ? "Unlimited ♾️" : String(record.tokens);

  const embed = {
    color: blStatus ? 0xe74c3c : roleColors[record.role],
    title: `👤 User Info — ${target.username}`,
    thumbnail: { url: target.displayAvatarURL() },
    fields: [
      { name: "User ID", value: target.id, inline: true },
      { name: "Role", value: roleLabels[record.role], inline: true },
      { name: "Tokens", value: tokenDisplay, inline: true },
      { name: "Commands Used", value: String(record.commandsUsed), inline: true },
      { name: "Blacklisted", value: blField, inline: false },
    ],
    footer: { text: "Lua Dumper Bot" },
  };

  await msg.reply({ embeds: [embed] });
}
