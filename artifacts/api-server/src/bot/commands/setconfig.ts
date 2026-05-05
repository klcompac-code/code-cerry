import { Message } from "discord.js";
import { config, isOwner } from "../config";

const BOOL_KEYS: Record<string, keyof typeof config> = {
  allow_dm: "allowDmCommands",
};

export async function setConfigCommand(msg: Message) {
  if (!isOwner(msg.author.id)) {
    await msg.reply("🚫 Only bot owners can use this command.");
    return;
  }

  const parts = msg.content.split(/\s+/);
  const key = parts[1]?.toLowerCase();
  const val = parts[2]?.toLowerCase();

  if (!key || !val) {
    await msg.reply("Usage: `.setconfig <key> <true|false>`\nKeys: `allow_dm`");
    return;
  }

  const configKey = BOOL_KEYS[key];
  if (!configKey) {
    await msg.reply(`Unknown key \`${key}\`. Valid keys: \`allow_dm\``);
    return;
  }

  if (val !== "true" && val !== "false") {
    await msg.reply("Value must be `true` or `false`.");
    return;
  }

  (config as Record<string, boolean>)[configKey] = val === "true";

  const embed = {
    color: 0x2ecc71,
    title: "⚙️ Config Updated",
    fields: [
      { name: "Key",       value: `\`${key}\``,                          inline: true },
      { name: "New Value", value: val === "true" ? "✅ true" : "❌ false", inline: true },
    ],
    footer: { text: `Updated by ${msg.author.username}` },
  };

  await msg.reply({ embeds: [embed] });
}
