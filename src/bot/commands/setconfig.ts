import { Message } from "discord.js";
import { config, isOwner } from "../config";
import { stopAutoUpdate, startAutoUpdate } from "../autoupdate";
import { getClient } from "../index";

const BOOL_KEYS: Record<string, keyof typeof config> = {
  allow_dm: "allowDmCommands",
  block_os: "blockOsLibrary",
  auto_update: "autoUpdateEnabled",
};

export async function setConfigCommand(msg: Message) {
  if (!isOwner(msg.author.id)) {
    await msg.reply("🚫 Hanya bot owner yang bisa menggunakan command ini.");
    return;
  }

  const parts = msg.content.split(/\s+/);
  const key = parts[1]?.toLowerCase();
  const val = parts[2]?.toLowerCase();

  if (!key || !val) {
    await msg.reply(
      "Usage: `.setconfig <key> <true|false>`\n" +
      "Keys: `allow_dm` · `block_os` · `auto_update`"
    );
    return;
  }

  const configKey = BOOL_KEYS[key];
  if (!configKey) {
    await msg.reply(`Key \`${key}\` tidak dikenal. Gunakan: \`allow_dm\`, \`block_os\`, \`auto_update\``);
    return;
  }

  if (val !== "true" && val !== "false") {
    await msg.reply("Value harus `true` atau `false`.");
    return;
  }

  const newVal = val === "true";
  (config as Record<string, boolean>)[configKey] = newVal;

  if (key === "auto_update") {
    if (newVal) {
      const client = getClient();
      if (client) startAutoUpdate(client);
    } else {
      stopAutoUpdate();
    }
  }

  const embed = {
    color: 0x2ecc71,
    title: "⚙️ Config Updated",
    fields: [
      { name: "Key", value: `\`${key}\``, inline: true },
      { name: "New Value", value: newVal ? "✅ true" : "❌ false", inline: true },
    ],
    footer: { text: `Updated by ${msg.author.username}` },
  };

  await msg.reply({ embeds: [embed] });
}
