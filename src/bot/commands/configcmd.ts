import { Message } from "discord.js";
import { config, isOwner } from "../config";

export async function configCommand(msg: Message) {
  if (!isOwner(msg.author.id)) {
    await msg.reply("🚫 Hanya bot owner yang bisa menggunakan command ini.");
    return;
  }

  const coOwnerList = config.coOwnerIds.length
    ? config.coOwnerIds.map((id) => `<@${id}>`).join(", ")
    : "_Belum ada_";

  const intervalMin = Math.floor(config.autoUpdateIntervalMs / 60000);

  const embed = {
    color: 0xe67e22,
    title: "⚙️ Bot Configuration",
    fields: [
      { name: "Free Default Tokens", value: String(config.freeDefaultTokens), inline: true },
      { name: "Premium Default Tokens", value: String(config.premiumDefaultTokens), inline: true },
      { name: "\u200b", value: "\u200b", inline: true },
      { name: "Free Max Tokens", value: String(config.freeMaxTokens), inline: true },
      { name: "Premium Max Tokens", value: String(config.premiumMaxTokens), inline: true },
      { name: "\u200b", value: "\u200b", inline: true },
      { name: "Token Restore Amount", value: `+${config.tokenRestoreAmount} / hour`, inline: true },
      { name: "Allow DM Commands", value: config.allowDmCommands ? "✅ Yes" : "❌ No (owner/coowner exempt)", inline: true },
      { name: "Block os Library", value: config.blockOsLibrary ? "✅ Yes" : "❌ No", inline: true },
      { name: "Auto-Update", value: config.autoUpdateEnabled ? `✅ Aktif (setiap ${intervalMin} menit)` : "❌ Nonaktif", inline: true },
      { name: "\u200b", value: "\u200b", inline: true },
      { name: "\u200b", value: "\u200b", inline: true },
      { name: "Co-Owners", value: coOwnerList, inline: false },
    ],
    description:
      "**Toggle boolean:** `.setconfig <key> <true|false>`\n" +
      "Keys: `allow_dm` · `block_os` · `auto_update`\n\n" +
      "**Set angka:** `.settoken config <key> <value>`\n" +
      "**Co-owner:** `.setcoowner add/remove/list <userId>`",
    footer: { text: "Lua Dumper Bot • Owner Panel" },
  };

  await msg.reply({ embeds: [embed] });
}
